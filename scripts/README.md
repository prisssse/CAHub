# Windows 右键菜单集成

## 功能说明

在任意文件夹上右键，可以直接选择"使用 CodeAgent Hub 打开"，应用会自动：

1. 查找该路径对应的项目
2. 如果项目存在且有会话，打开最近的会话
3. 如果项目存在但无会话，创建新会话
4. 如果项目不存在，自动创建新会话

## 安装步骤

### 方式一：自动安装（推荐）

1. 右键点击 `install_context_menu.reg`
2. 选择"合并"
3. 在弹出的警告中点击"是"
4. 完成！

### 方式二：手动修改路径后安装

如果你的安装路径不是默认的 `C:\Program Files\CodeAgent Hub\`，需要：

1. 用文本编辑器打开 `install_context_menu.reg`
2. 将所有 `C:\\Program Files\\CodeAgent Hub\\codeagent_hub.exe` 替换为你的实际安装路径
   - 注意：路径中的反斜杠需要双写（如 `C:\\MyApps\\CodeAgentHub\\app.exe`）
3. 保存后右键点击文件，选择"合并"
4. 在弹出的警告中点击"是"

## 卸载

右键点击 `uninstall_context_menu.reg`，选择"合并"即可移除右键菜单。

## 使用

安装后，在任意文件夹上：

- **右键文件夹本身**：选择"使用 CodeAgent Hub 打开"
- **在文件夹内空白处右键**：选择"在此处使用 CodeAgent Hub"

应用会自动启动并打开该文件夹的对话。

## 常见问题

**Q: 右键菜单没有出现？**

A: 检查注册表文件中的路径是否正确，确保指向实际的 exe 文件。

**Q: 点击右键菜单没反应？**

A: 确保应用已正确安装，并且路径中没有特殊字符。

**Q: 想修改菜单文字？**

A: 编辑 `install_context_menu.reg`，修改 `@="使用 CodeAgent Hub 打开"` 中的文字。
