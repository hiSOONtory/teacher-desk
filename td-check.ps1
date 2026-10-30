# 교사 대시보드 점검 도구 — '대시보드_점검.bat'을 더블클릭하면 실행된다.
# 대시보드가 자꾸 처음으로 돌아갈 때 원인을 찾고, 디스크 캐시가 꺼져 있으면 켜 준다.
$ErrorActionPreference = 'SilentlyContinue'
$out = New-Object System.Collections.Generic.List[string]
function Say($t) { $out.Add($t); Write-Host $t }

Say "교사 대시보드 점검  $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
Say ""

$store = Get-ChildItem "$env:LOCALAPPDATA\Packages" -Directory -Filter "*LivelyWallpaper*" | Select-Object -First 1
$bases = @()
if ($store) { $bases += Join-Path $store.FullName "LocalCache\Local\Lively Wallpaper" }
$bases += "$env:LOCALAPPDATA\Lively Wallpaper"
$base = $bases | Where-Object { Test-Path (Join-Path $_ "Settings.json") } | Select-Object -First 1
if (-not $base) {
    Say "[X] Lively 설정 파일을 못 찾았어요. Lively를 한 번 켰다가 끄고 다시 실행해 주세요."
    Read-Host "엔터를 누르면 닫혀요"; exit
}
$sf = Join-Path $base "Settings.json"
$s = [IO.File]::ReadAllText($sf) | ConvertFrom-Json

# 1. 디스크 캐시 (꺼져 있으면 Lively가 대시보드를 다시 띄울 때마다 내용이 사라진다)
$cache = [bool]$s.CefDiskCache
if ($cache) { Say "[O] 디스크 캐시: 켜짐" }
else { Say "[X] 디스크 캐시: 꺼짐  <- 리셋 원인! Lively가 대시보드를 다시 띄울 때마다(화면 꺼짐·잠금 뒤 등) 내용이 사라져요." }

# 2. 화면 배치 (화면별이면 모니터마다 저장이 따로)
$arr = [int]$s.WallpaperArrangement
$arrName = @{ 0 = "화면별"; 1 = "확장"; 2 = "복제" }[$arr]
if ($arr -eq 0) { Say "[!] 화면 배치: $arrName  <- 모니터가 두 대면 화면마다 저장이 따로라 한쪽이 비어 보여요. '복제'를 추천해요." }
else { Say "[O] 화면 배치: $arrName" }

# 3. 대시보드 저장 폴더
$ls = Get-ChildItem (Join-Path $base "WebView2") -Recurse -Directory -Filter "leveldb" |
      Where-Object { $_.FullName -match 'Local Storage' -and $_.FullName -notmatch 'Lively\.UI' }
if (-not $ls) { Say "[X] 대시보드 저장 폴더가 없어요 (디스크 캐시가 꺼져 있으면 임시 폴더를 써서 남지 않아요)." }
foreach ($l in $ls) {
    $files = Get-ChildItem $l.FullName -File
    $has = $false
    foreach ($f in $files) {
        try { if ([Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($f.FullName)).Contains('teacherDesk')) { $has = $true } } catch {}
    }
    $last = ($files | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
    $name = $l.FullName -replace '^.*\\WebView2\\', '' -replace '\\EBWebView.*$', ''
    if ($has) { Say "[O] 저장 폴더($name): 대시보드 기록 있음, 마지막 저장 $last" }
    else { Say "[X] 저장 폴더($name): 대시보드 기록 없음" }
}

# 4. 오늘 Lively 기록 (대시보드를 새로 띄운 횟수 = 리셋될 수 있었던 순간)
$today = Get-Date -Format 'yyyy-MM-dd'
$lines = Get-ChildItem (Join-Path $base "logs") -File | Sort-Object LastWriteTime -Descending | Select-Object -First 3 |
         ForEach-Object { Get-Content $_.FullName } | Where-Object { $_ -like "$today*" }
$sets = @($lines | Where-Object { $_ -match 'Setting wallpaper' }).Count
$dead = @($lines | Where-Object { $_ -match 'exited with exit code|Unresponsive|Terminated' }).Count
Say "[i] 오늘 대시보드를 새로 띄운 횟수: $sets / 멈추거나 꺼진 횟수: $dead"

# 5. 메모리 (모자라면 대시보드가 멈추거나 꺼진다)
$os = Get-CimInstance Win32_OperatingSystem
$free = $os.FreePhysicalMemory / 1MB
Say ("[{0}] 메모리: 전체 {1:N1}GB, 남은 {2:N1}GB" -f $(if ($free -lt 1.5) { '!' } else { 'O' }), ($os.TotalVisibleMemorySize / 1MB), $free)
if ($free -lt 1.5) { Say "    메모리가 빠듯해요. 안 쓰는 크롬 탭·프로그램을 닫으면 대시보드가 덜 멈춰요." }

# 디스크 캐시 고치기
if (-not $cache) {
    Say ""
    $ans = Read-Host "디스크 캐시를 지금 켤까요? Lively가 잠깐 꺼졌다 다시 켜져요. (Y/N)"
    if ($ans -match '^[yY]') {
        Get-Process | Where-Object { $_.ProcessName -match '^Lively' } | Stop-Process -Force
        Start-Sleep -Seconds 3
        Copy-Item $sf "$sf.before-check" -Force
        $t = [IO.File]::ReadAllText($sf) -replace '"CefDiskCache":\s*false', '"CefDiskCache": true'
        [IO.File]::WriteAllText($sf, $t, (New-Object Text.UTF8Encoding $false))
        $ok = [bool]([IO.File]::ReadAllText($sf) | ConvertFrom-Json).CefDiskCache
        if ($store) { Start-Process explorer.exe "shell:AppsFolder\$($store.Name)!App" }   # Packages 폴더 이름 = 앱 이름(패밀리 이름)
        if ($ok) { Say "[O] 디스크 캐시를 켰어요. Lively가 다시 뜨면 학교·시간표를 한 번만 다시 넣고, 설정 -> 백업 · 초기화 -> 백업 파일 저장을 해 두세요." }
        else { Say "[X] 디스크 캐시를 켜지 못했어요. Lively를 완전히 끄고 Settings.json을 직접 고쳐 주세요: $sf" }
        if (-not $store) { Say "    Lively를 직접 다시 실행해 주세요." }
    }
}

$desk = [Environment]::GetFolderPath('Desktop')
$report = Join-Path $desk "대시보드_점검결과.txt"
$out | Set-Content -Path $report -Encoding UTF8
Write-Host ""
Write-Host "결과를 바탕화면 '대시보드_점검결과.txt'에 저장했어요. 문제가 계속되면 이 파일을 보내 주세요."
Read-Host "엔터를 누르면 닫혀요"
