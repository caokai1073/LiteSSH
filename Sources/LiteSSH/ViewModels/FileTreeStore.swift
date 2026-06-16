// 这个文件已废弃，不再被任何地方引用。
//
// 早期版本侧边栏文件浏览用的是「原地展开的树」（这个 FileTreeStore 管理树状态，配合
// OutlineGroup 渲染），现在改成了：点服务器行最右边的文件夹图标，整个侧边栏切换成该
// 服务器「当前目录」的平铺列表，用一个更简单的「当前路径 + 返回栈」模型——
// 见 ViewModels/FileBrowserStore.swift，被 SessionStore.fileBrowserStore(for:) 管理生命周期。
//
// 留着这个空文件只是因为工具权限不允许我直接删除磁盘上的文件；在 Finder 里
// 把它删掉是安全的，不影响编译（SwiftPM 不会因为多一个空文件报错）。
