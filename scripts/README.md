# ParaBank 一键运行 GitHub SOAtest 测试

在项目根目录双击 `run-action-test.bat`，或在 PowerShell 中执行：

```powershell
.\run-action-test.bat
```

脚本默认测试 `parasoft/run-soatest-action@master`，执行 `Smoke.tst`，提交并推送到本仓库的 `master` 分支，然后等待 GitHub Actions 执行完成。双击执行后窗口会保留，便于查看结果。

默认配置：

| 项目 | 配置 |
| --- | --- |
| Runner 启动文件 | `D:\Github-runner\parabank-soatest-runner\run.cmd` |
| Runner 注册名 | 从 `.runner` 读取，当前为 `CD-LYAO-02` |
| 调度标签 | `self-hosted`, `Windows`, `X64`, `CD-LYAO-02` |
| SOAtest | `C:\Program Files\Parasoft\SOAtest & Virtualize\2026.2` |
| ParaBank | `http://localhost:8080/parabank/` |
| 工作流 | `.github/workflows/action-test.yml` |
| 测试套件 | `Smoke.tst` |

`self-hosted` 是标签，Runner 的注册名为 `CD-LYAO-02`。脚本会核对 Runner 注册仓库，并在需要时添加与注册名相同的自定义调度标签，保留已有标签，确保任务交给指定 Runner。

## 指定 Action 分支或测试套件

```powershell
.\run-action-test.bat -ActionRef feature/my-fix
.\run-action-test.bat -ActionRef 1.0.0
.\run-action-test.bat -ActionRepository lyao-parasoft/run-soatest-action -ActionRef master
.\run-action-test.bat -Suite PB-ParabankServices-v3.tst
.\run-action-test.bat -Suite PB-Bookstore2.tst
```

可选套件：`Smoke.tst`、`PB-ParabankServices-v3.tst`、`PB-WebUI-v3.tst`、`PB-Bookstore1.tst`、`PB-Bookstore2.tst`。原有 ParaBank Services 和 Web UI 套件包含覆盖率工具，需要对应的扩展和 `localhost:8050` 覆盖率服务；Web UI 还需要可用的浏览器及驱动。脚本不会把这些独立服务的端口改成 `8080`。默认的 Smoke 套件不包含这些覆盖率工具。

也可以直接调用 PowerShell 脚本，不经过批处理窗口：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-ActionTest.ps1 -ActionRef master -Wait
.\scripts\Invoke-ActionTest.ps1 -Branch master -Remote origin -Wait -WaitMinutes 45
.\scripts\Invoke-ActionTest.ps1 -InstallDir 'C:\Program Files\Parasoft\SOAtest & Virtualize\2026.1' -Wait
```

只准备本地工作流供检查，不启动 Runner、不访问 GitHub、不提交或推送：

```powershell
.\scripts\Invoke-ActionTest.ps1 -ActionRef feature/my-fix -PrepareOnly
git diff -- .github/workflows/action-test.yml
```

## 运行流程

1. 检查当前分支、空暂存区、Runner 注册仓库及 SOAtest 安装。
2. 检查 Action ref，并确认本地提交包含远程分支的全部提交；不自动合并或强推。
3. 核对并启动指定 Runner，等待连接和监听日志，再检查 GitHub 中的在线状态；已有同目录 Listener 时复用。
4. 更新独立的 `action-test.yml`，写入被测 Action、套件、Runner 标签和唯一运行标记。原有工作流不受影响。
5. 只提交脚本明确列出的自动化文件，然后推送。每次唯一标记使连续测试同一 Action ref 也能触发新运行。其他源代码修改应先自行提交，才能进入 GitHub 检出的版本。
6. 查询此次 commit 对应的工作流，输出运行链接；批处理入口默认等待结束，失败时返回非零退出码。
7. GitHub 工作流构建 ParaBank、导入 TestAssets/Bookstore、启动服务、执行被测 Action、校验真实执行数大于零和 xUnit 报告，并上传报告。工作流结束时仅停止本次启动的服务，Runner 保持运行。

脚本使用当前 Windows 用户权限启动最小化 Runner 窗口。已经以其他用户或管理员身份启动且不可见的 Runner 仍可能导致启动冲突；可关闭对应 Runner 控制台后重试。

服务已在 `8080` 正常运行时会复用。原有测试会清理或修改 ParaBank 示例数据，因此执行套件会影响该实例的数据。需要全新隔离实例时，先停止现有 ParaBank，再运行本脚本。`8080`、`9001`、`61616`、`8205` 必须可用。

## 凭据、许可证和运行文件

需要 Windows PowerShell 5.1、Git、Maven 3.6.3+、JDK，以及有效的 SOAtest 许可证。GitHub 工作流会设置 Zulu JDK 17。

GitHub API 凭据优先使用 `GH_TOKEN` 或 `GITHUB_TOKEN`，否则复用 Git Credential Manager 已保存的 GitHub 凭据。凭据需要能读取 Action ref、读取 Actions、管理仓库 Runner 标签；Git push 还需要仓库及 workflow 写权限。令牌不会输出或写入仓库。

SOAtest 默认继承执行用户的本机许可证配置。如需补充设置，可在 Runner 用户环境中设置 `SOATEST_LOCAL_SETTINGS`，指向本机私有 `.properties` 文件，或配置仓库 Secret `SOATEST_SETTINGS`。工作流使用临时设置文件，避免读取仓库里历史遗留的本机/服务器配置。设置文件不会上传，结束时会删除。

运行状态和报告保存在已忽略的 `.runtime/`：

- Runner 日志：`.runtime/runner/console.log`
- ParaBank 日志：`.runtime/parabank.stdout.log`、`.runtime/parabank.stderr.log`
- 独立 SOAtest workspace：`.runtime/soatest-workspace/`
- 原生 XML/HTML 及 xUnit：`.runtime/reports/ci/`（GitHub 检出目录内）

报告也会作为 `parabank-soatest-<run-id>-<attempt>` Artifact 上传到 GitHub 运行页面。SOAtest 本身的断言、许可证、扩展或浏览器错误会如实使工作流失败。

## 单独启动组件

```powershell
.\scripts\Start-Runner.ps1
.\scripts\Start-Parabank.ps1
.\scripts\Stop-Parabank.ps1
.\scripts\Initialize-Soatest.ps1
```

只启动应用仍可以使用根目录原有的 `start.bat`；`run-action-test.bat` 用于提交、推送并触发 GitHub 测试。
