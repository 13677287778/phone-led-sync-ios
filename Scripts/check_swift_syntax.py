from pathlib import Path
import tree_sitter,tree_sitter_swift
root=Path(r'E:\USB\phone-led-sync-ios')
parser=tree_sitter.Parser(tree_sitter.Language(tree_sitter_swift.language()))
errors=[]
for p in root.rglob('*.swift'):
    tree=parser.parse(p.read_bytes())
    def walk(n):
        if n.type=='ERROR' or n.is_missing:errors.append((str(p.relative_to(root)),n.type,n.start_point,n.end_point))
        for c in n.children:walk(c)
    walk(tree.root_node)
print('Swift grammar errors:',errors)
if errors:raise SystemExit(1)
print('PASS syntax grammar for',len(list(root.rglob('*.swift'))),'Swift files (not Xcode type checking).')
