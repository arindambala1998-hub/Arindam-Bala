Start-Transcript -Path ("flutter_audit_{0}.txt" -f (Get-Date -Format yyyyMMdd_HHmmss)) -Force

Write-Host "===== 🧩 SYSTEM ====="
flutter --version
dart --version
try { java -version } catch {}
Get-Command gradle -ErrorAction SilentlyContinue | Out-Host
Get-Command xcodebuild -ErrorAction SilentlyContinue | Out-Host

Write-Host "`n===== 🩺 flutter doctor ====="
flutter doctor -v

Write-Host "`n===== 📁 PROJECT ROOT ====="
Get-Location
Get-ChildItem -Force | Out-Host

Write-Host "`n===== 📦 pubspec.yaml ====="
if (Test-Path pubspec.yaml) { Get-Content pubspec.yaml } else { "No pubspec.yaml" }

Write-Host "`n===== 🗂️ lib/ structure ====="
if (Test-Path lib) { Get-ChildItem lib -Recurse | Out-Host } else { "No lib/ folder" }

Write-Host "`n===== 🔥 Firebase (if any) ====="
if (Test-Path android/app/google-services.json) { "Found android google-services.json (do NOT share publicly)" }
if (Test-Path ios/Runner/GoogleService-Info.plist) { "Found iOS GoogleService-Info.plist (do NOT share publicly)" }

Write-Host "`n===== ⚙️ Android Gradle ====="
if (Test-Path android/app/build.gradle) { Get-Content android/app/build.gradle -TotalCount 200 } else {"No android/app/build.gradle"}
if (Test-Path android/build.gradle) { Get-Content android/build.gradle -TotalCount 200 }
if (Test-Path android/gradle.properties) { Get-Content android/gradle.properties -TotalCount 200 }

Write-Host "`n===== 🍏 iOS Config (summary only) ====="
if (Test-Path ios/Runner.xcodeproj/project.pbxproj) { "iOS project present (pbxproj exists)" } else { "No iOS project" }

Write-Host "`n===== 🧪 Tests (if any) ====="
if (Test-Path test) { Get-ChildItem test -Recurse | Out-Host } else { "No test folder" }

Write-Host "`n===== 🔀 Flavors (guess) ====="
$dartFiles = Get-ChildItem -Recurse -Include *.dart -Exclude build -ErrorAction SilentlyContinue
if ($dartFiles) {
  Select-String -Path $dartFiles.FullName -Pattern 'flavor|--flavor|main_dev\.dart|main_prod\.dart' -ErrorAction SilentlyContinue | Out-Host
} else { "No dart files found" }

Write-Host "`n===== 📄 README ====="
if (Test-Path README.md) { Get-Content README.md -TotalCount 200 } else { "No README.md" }

Stop-Transcript
