[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ManifestPath,

    [string]$OutputPath
)

. (Join-Path $PSScriptRoot "utils.ps1")

if (-not $OutputPath) {
    $OutputPath = Join-Path (Split-Path $ManifestPath) "manifest-viewer.html"
}

if (-not (Test-Path $ManifestPath)) {
    Log "Manifest file not found: $ManifestPath" 'ERROR'
    return
}

Log "Reading manifest and generating HTML viewer..." 'INFO'
$rawLines = Get-Content $ManifestPath
# Filter out empty lines and force type to raw string to strip PSObject properties
$paths = $rawLines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { [string]$_ }

# Convert to JSON array
$jsonPaths = $paths | ConvertTo-Json -Compress

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Migratron Archive Viewer</title>
    <style>
        :root {
            --bg-color: #0f172a;
            --panel-bg: #1e293b;
            --text-main: #f8fafc;
            --text-muted: #94a3b8;
            --accent: #38bdf8;
            --accent-hover: #0ea5e9;
            --border: #334155;
            --folder-icon: #fcd34d;
        }
        body {
            font-family: 'Segoe UI', Inter, Roboto, sans-serif;
            background-color: var(--bg-color);
            color: var(--text-main);
            margin: 0;
            padding: 2rem;
            line-height: 1.5;
        }
        .container {
            max-width: 1000px;
            margin: 0 auto;
        }
        header {
            margin-bottom: 2rem;
        }
        h1 {
            margin: 0;
            font-size: 1.8rem;
            font-weight: 600;
        }
        .subtitle {
            color: var(--text-muted);
            margin-top: 0.5rem;
        }
        .search-container {
            margin-bottom: 1.5rem;
        }
        input[type="text"] {
            width: 100%;
            padding: 0.75rem 1rem;
            background-color: var(--panel-bg);
            border: 1px solid var(--border);
            border-radius: 8px;
            color: var(--text-main);
            font-size: 1rem;
            outline: none;
            transition: border-color 0.2s;
        }
        input[type="text"]:focus {
            border-color: var(--accent);
        }
        .tree-container {
            background-color: var(--panel-bg);
            border: 1px solid var(--border);
            border-radius: 8px;
            padding: 1.5rem;
            max-height: 70vh;
            overflow-y: auto;
        }
        ul {
            list-style-type: none;
            padding-left: 1.5rem;
            margin: 0;
        }
        .tree-container > ul {
            padding-left: 0;
        }
        li {
            margin: 0.2rem 0;
        }
        .item {
            display: flex;
            align-items: center;
            cursor: pointer;
            padding: 0.35rem 0.5rem;
            border-radius: 6px;
            transition: background-color 0.15s;
        }
        .item:hover {
            background-color: rgba(255, 255, 255, 0.05);
        }
        .caret {
            width: 20px;
            display: inline-block;
            text-align: center;
            color: var(--text-muted);
            transition: transform 0.2s;
            user-select: none;
            font-size: 0.8em;
        }
        .caret-down {
            transform: rotate(90deg);
        }
        .icon {
            margin-right: 0.6rem;
            font-size: 1.1em;
        }
        .folder { color: var(--folder-icon); }
        .file { color: var(--text-muted); }
        .name {
            flex-grow: 1;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }
        .count {
            color: var(--text-muted);
            font-size: 0.8em;
            background: rgba(0,0,0,0.3);
            padding: 0.15rem 0.6rem;
            border-radius: 12px;
            margin-left: 1rem;
        }
        .hidden { display: none !important; }
        
        /* Scrollbar */
        ::-webkit-scrollbar {
            width: 8px;
            height: 8px;
        }
        ::-webkit-scrollbar-track {
            background: var(--bg-color); 
        }
        ::-webkit-scrollbar-thumb {
            background: var(--border); 
            border-radius: 4px;
        }
        ::-webkit-scrollbar-thumb:hover {
            background: var(--text-muted); 
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>Migratron Archive Viewer</h1>
            <div class="subtitle">Total Files Captured: <span id="total-count">0</span></div>
        </header>
        <div class="search-container">
            <input type="text" id="search" placeholder="Search folders or files... (e.g. cygwin, AppData)">
        </div>
        <div class="tree-container" id="tree-root">
            <div style="color: var(--text-muted)">Loading interactive tree...</div>
        </div>
    </div>

    <script>
        const paths = $jsonPaths;
        
        // Build Tree
        const tree = { name: "Root", children: {}, files: 0, isDir: true };
        
        paths.forEach(p => {
            // Strip long path prefixes and split
            const cleanPath = p.replace(/^\\\\\?\\/, '');
            const parts = cleanPath.split('\\').filter(Boolean);
            
            let current = tree;
            for (let i = 0; i < parts.length; i++) {
                const part = parts[i];
                const isLast = (i === parts.length - 1);
                
                if (!current.children[part]) {
                    current.children[part] = {
                        name: part,
                        children: {},
                        files: 0,
                        isDir: !isLast
                    };
                }
                
                if (isLast) {
                    current.children[part].files++;
                } else {
                    current.files++;
                }
                current = current.children[part];
            }
        });

        document.getElementById('total-count').textContent = paths.length.toLocaleString();

        function renderNode(node, isRoot = false) {
            const ul = document.createElement('ul');
            if (!isRoot) ul.classList.add('hidden');

            const keys = Object.keys(node.children).sort((a, b) => {
                const aNode = node.children[a];
                const bNode = node.children[b];
                if (aNode.isDir && !bNode.isDir) return -1;
                if (!aNode.isDir && bNode.isDir) return 1;
                return a.localeCompare(b, undefined, {numeric: true, sensitivity: 'base'});
            });

            keys.forEach(k => {
                const child = node.children[k];
                const li = document.createElement('li');
                
                const itemDiv = document.createElement('div');
                itemDiv.className = 'item';
                
                if (child.isDir) {
                    const caret = document.createElement('span');
                    caret.className = 'caret';
                    caret.textContent = '▶';
                    itemDiv.appendChild(caret);
                    
                    const icon = document.createElement('span');
                    icon.className = 'icon folder';
                    icon.textContent = '📁';
                    itemDiv.appendChild(icon);
                } else {
                    const spacer = document.createElement('span');
                    spacer.className = 'caret';
                    itemDiv.appendChild(spacer);
                    
                    const icon = document.createElement('span');
                    icon.className = 'icon file';
                    icon.textContent = '📄';
                    itemDiv.appendChild(icon);
                }

                const nameSpan = document.createElement('span');
                nameSpan.className = 'name';
                nameSpan.textContent = child.name;
                nameSpan.title = child.name;
                itemDiv.appendChild(nameSpan);

                if (child.isDir && child.files > 0) {
                    const countSpan = document.createElement('span');
                    countSpan.className = 'count';
                    countSpan.textContent = child.files.toLocaleString() + ' files';
                    itemDiv.appendChild(countSpan);
                }

                li.appendChild(itemDiv);
                li.dataset.name = child.name.toLowerCase();

                if (child.isDir) {
                    const childUl = renderNode(child);
                    li.appendChild(childUl);
                    
                    itemDiv.addEventListener('click', (e) => {
                        e.stopPropagation();
                        childUl.classList.toggle('hidden');
                        const caret = itemDiv.querySelector('.caret');
                        if (childUl.classList.contains('hidden')) {
                            caret.textContent = '▶';
                            caret.classList.remove('caret-down');
                        } else {
                            caret.textContent = '▼';
                            caret.classList.add('caret-down');
                        }
                    });
                }
                
                ul.appendChild(li);
            });
            return ul;
        }

        const rootUl = renderNode(tree, true);
        const container = document.getElementById('tree-root');
        container.innerHTML = '';
        container.appendChild(rootUl);

        // Search Filter
        const searchInput = document.getElementById('search');
        let searchTimeout;
        searchInput.addEventListener('input', (e) => {
            clearTimeout(searchTimeout);
            const term = e.target.value.toLowerCase();
            
            searchTimeout = setTimeout(() => {
                const allItems = rootUl.querySelectorAll('li');
                
                if (!term) {
                    allItems.forEach(li => {
                        li.classList.remove('hidden');
                        const ul = li.querySelector('ul');
                        if (ul) {
                            ul.classList.add('hidden');
                            const caret = li.querySelector('.caret');
                            if(caret) {
                                caret.textContent = '▶';
                                caret.classList.remove('caret-down');
                            }
                        }
                    });
                    return;
                }

                allItems.forEach(li => {
                    const name = li.dataset.name;
                    if (name.includes(term)) {
                        li.classList.remove('hidden');
                        let parent = li.parentElement;
                        while (parent && parent.tagName === 'UL') {
                            parent.classList.remove('hidden');
                            const parentLi = parent.parentElement;
                            if (parentLi && parentLi.tagName === 'LI') {
                                parentLi.classList.remove('hidden');
                                const caret = parentLi.querySelector('.caret');
                                if(caret) {
                                    caret.textContent = '▼';
                                    caret.classList.add('caret-down');
                                }
                            }
                            parent = parentLi ? parentLi.parentElement : null;
                        }
                    } else {
                        // Only hide if it doesn't contain a match in its children
                        const hasVisibleChild = Array.from(li.querySelectorAll('li')).some(child => child.dataset.name.includes(term));
                        if (!hasVisibleChild) {
                            li.classList.add('hidden');
                        } else {
                            li.classList.remove('hidden');
                            const ul = li.querySelector('ul');
                            if (ul) ul.classList.remove('hidden');
                            const caret = li.querySelector('.caret');
                            if(caret) {
                                caret.textContent = '▼';
                                caret.classList.add('caret-down');
                            }
                        }
                    }
                });
            }, 300);
        });

    </script>
</body>
</html>
"@

$html | Out-File -FilePath $OutputPath -Encoding utf8
Log "Interactive Viewer generated at: $OutputPath" 'SUCCESS'
