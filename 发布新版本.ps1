<#
  一键发布新版本（零成本更新通道）
  用法：
    cd "D:\Mod 管理器\update-repo"
    .\发布新版本.ps1 -RepoUrl https://github.com/你的用户名/仓库名.git
  首次会弹 GitHub 登录窗（Windows 凭据管理器），登录一次以后就记住了。
#>
param(
  [Parameter(Mandatory=$false)][string]$RepoUrl = "",
  [Parameter(Mandatory=$false)][string]$ApkPath = "",
  [Parameter(Mandatory=$false)][string]$Note = ""
)

$ErrorActionPreference = 'Stop'
$repoDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$distDir = Join-Path (Split-Path -Parent $repoDir) 'dist'
$apkName = 'deadcells-mod-manager.apk'
$aapt = 'D:\AndroidSdk\build-tools\34.0.0\aapt2.exe'

Write-Host "== 1/4 找最新的安装包 ==" -ForegroundColor Cyan
if (-not $ApkPath) {
  $cand = Get-ChildItem $distDir -Filter '*.apk' |
          Where-Object { $_.Name -like '死亡细胞模组管理器_手机版*' } |
          Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $cand) { throw "dist 里没找到 死亡细胞模组管理器_手机版*.apk" }
  $ApkPath = $cand.FullName
}
Write-Host "   $ApkPath"

Write-Host "== 2/4 读版本号 ==" -ForegroundColor Cyan
$badging = & $aapt dump badging $ApkPath 2>$null | Select-String '^package:'
if (-not $badging) { throw "读不出 APK 版本（aapt2 路径对吗：$aapt）" }
$vc = [regex]::Match($badging.Line, "versionCode='(\d+)'").Groups[1].Value
$vn = [regex]::Match($badging.Line, "versionName='([^']+)'").Groups[1].Value
Write-Host "   versionName=$vn versionCode=$vc"

Write-Host "== 3/4 拷贝 APK + 生成 version.json ==" -ForegroundColor Cyan
Copy-Item $ApkPath (Join-Path $repoDir $apkName) -Force

if (-not $RepoUrl) {
  Push-Location $repoDir
  try { $RepoUrl = (git remote get-url origin 2>$null) } catch { $RepoUrl = "" }
  Pop-Location
}
if (-not $RepoUrl) { throw "请用 -RepoUrl 指定仓库地址，例如 https://github.com/用户名/仓库名.git" }

$m = [regex]::Match($RepoUrl, 'github\.com[/:]([^/]+)/([^/]+?)(\.git)?$')
if (-not $m.Success) { throw "看不懂这个仓库地址：$RepoUrl" }
$user = $m.Groups[1].Value
$repo = $m.Groups[2].Value
$rawUrl = "https://raw.githubusercontent.com/$user/$repo/main/$apkName"

$json = [ordered]@{
  versionCode = [int64]$vc
  versionName = $vn
  url         = $rawUrl
  note        = $Note
} | ConvertTo-Json -Compress
Set-Content -Path (Join-Path $repoDir 'version.json') -Value $json -Encoding UTF8
Write-Host "   $json"

Write-Host "== 4/4 提交并推送 ==" -ForegroundColor Cyan
Push-Location $repoDir
try {
  if (-not (Test-Path (Join-Path $repoDir '.git'))) {
    git init | Out-Null
    git branch -M main
  }
  $hasRemote = $false
  try { git remote get-url origin | Out-Null; $hasRemote = $true } catch { $hasRemote = $false }
  if (-not $hasRemote) { git remote add origin $RepoUrl }

  if (-not (git config user.name))  { git config user.name  ($user) }
  if (-not (git config user.email)) { git config user.email "$user@users.noreply.github.com" }

  git add -A
  $msg = "release $vn ($vc)"
  git commit -m $msg
  git push -u origin main
  Write-Host ""
  Write-Host "== 完成 ==" -ForegroundColor Green
  Write-Host "更新地址：https://raw.githubusercontent.com/$user/$repo/main/version.json"
  Write-Host "下载直链：$rawUrl"
  Write-Host ""
  Write-Host "把这个地址填进 JsBridge.kt 的 UPDATE_JSON_URLS 第一条即可（只需填一次）："
  Write-Host "  https://raw.githubusercontent.com/$user/$repo/main/version.json" -ForegroundColor Yellow
}
finally { Pop-Location }
