#requires -Version 5.1
<#
.SYNOPSIS
    Driver & Runtime Manager — หน้าต่าง GUI สำหรับตรวจระบบ ตรวจชุดไดรเวอร์ทั้งหมด ดาวน์โหลดและติดตั้งไดรเวอร์
    (ผู้ผลิตก่อน แล้วจึงไดรเวอร์ที่ Microsoft รับรองซึ่งใหม่กว่า) ติดตั้งรันไทม์ โปรแกรมเสริม และไฟล์ติดตั้งทุกรูปแบบ

.DESCRIPTION
    โหมด Gui (ค่าเริ่มต้น): หน้าต่างติ๊กเลือกรายการ ทำงานเบื้องหลังโดยหน้าต่างไม่ค้าง
    โหมด Scan: ตรวจระบบอย่างละเอียดแล้วออกรายงาน HTML/JSON (เพิ่ม -CheckUpdates เพื่อตรวจอัปเดตด้วย)
    โหมด Install: ติดตั้งแบบไม่มีหน้าต่างตามชุด/รายการที่ระบุ
    โหมด SelfTest: ตรวจแคตตาล็อก โมดูล และหน้าต่าง XAML โดยไม่แตะระบบ

.EXAMPLE
    .\Start-DriverRuntimeManager.cmd
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\DriverRuntimeManager.ps1 -Mode Scan -CheckUpdates
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\DriverRuntimeManager.ps1 -Mode Install -Preset gaming -IncludeOem -IncludeWindowsUpdateDrivers -DryRun
#>
[CmdletBinding()]
param(
    [ValidateSet('Gui', 'Scan', 'Install', 'SelfTest')][string]$Mode = 'Gui',
    [ValidateSet('recommended', 'gaming', 'work', 'all', 'none')][string]$Preset = 'recommended',
    [string[]]$Items = @(),
    [string[]]$Files = @(),
    [switch]$IncludeOem,
    [switch]$IncludeWindowsUpdateDrivers,
    [switch]$CheckUpdates,
    [switch]$DryRun,
    [switch]$Reboot,
    [switch]$NoRestorePoint,
    [switch]$NoCleanup,
    [switch]$AllowUnsigned,
    [switch]$Resume,
    [switch]$NoElevate,
    [switch]$ShowConsole,
    [string]$Root,
    [string]$CatalogPath,
    [string]$LauncherPath
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ModulePath = Join-Path $ScriptDir 'DriverRuntimeManager.psm1'
if (-not $CatalogPath) { $CatalogPath = Join-Path $ScriptDir 'catalog.json' }
if (-not $LauncherPath) { $LauncherPath = Join-Path $ScriptDir 'Start-DriverRuntimeManager.cmd' }
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
# powershell -File ส่งค่าอาร์เรย์มาเป็นข้อความเดียว: แยก -Items ด้วย , และ -Files ด้วย ;
$Items = @($Items | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$Files = @($Files | ForEach-Object { $_ -split ';' } | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ })

Import-Module $ModulePath -Force -DisableNameChecking

# ---------------------------------------------------------------------------
# สิทธิ์ Administrator และ STA
# ---------------------------------------------------------------------------
function Get-RelaunchArguments {
    $list = New-Object System.Collections.Generic.List[string]
    $list.Add('-NoProfile'); $list.Add('-ExecutionPolicy'); $list.Add('Bypass'); $list.Add('-STA'); $list.Add('-File'); $list.Add(('"{0}"' -f $PSCommandPath))
    foreach ($k in $script:BoundParams.Keys) {
        $v = $script:BoundParams[$k]
        if ($v -is [switch] -or $v -is [bool]) { if ([bool]$v) { $list.Add("-$k") } }
        elseif ($v -is [array]) { if ($v.Count) { $list.Add("-$k"); $list.Add((($v | ForEach-Object { '"{0}"' -f $_ }) -join ',')) } }
        else { $list.Add("-$k"); $list.Add(('"{0}"' -f $v)) }
    }
    return ($list -join ' ')
}
$script:BoundParams = $PSBoundParameters

if ((Test-DrmIsWindows) -and $Mode -ne 'SelfTest' -and -not $NoElevate -and -not (Test-DrmIsAdmin)) {
    $exe = (Get-Process -Id $PID).Path
    Write-Host 'ต้องใช้สิทธิ์ Administrator — กำลังขอสิทธิ์ (UAC)...' -ForegroundColor Yellow
    try { Start-Process -FilePath $exe -ArgumentList (Get-RelaunchArguments) -Verb RunAs | Out-Null } catch { Write-Host 'ผู้ใช้ไม่อนุญาตสิทธิ์ Administrator' -ForegroundColor Red; exit 5 }
    exit 0
}
if ($Mode -eq 'Gui' -and [Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    $exe = (Get-Process -Id $PID).Path
    Start-Process -FilePath $exe -ArgumentList (Get-RelaunchArguments) | Out-Null
    exit 0
}

function Get-RunOptions {
    [pscustomobject]@{
        CreateRestorePoint = -not $NoRestorePoint
        BackupDrivers      = $false
        ResumeAfterReboot  = $true
        Reboot             = [bool]$Reboot
        AllowUnsigned      = [bool]$AllowUnsigned
        Cleanup            = -not $NoCleanup
        KeepDownloads      = $false
        CleanVendorFolders = $true
        CleanTemp          = $true
        CleanWuCache       = $false
        RemoveOldDrivers   = $false
        ComponentCleanup   = $false
    }
}

# ---------------------------------------------------------------------------
# โหมดคำสั่ง (ไม่มีหน้าต่าง)
# ---------------------------------------------------------------------------
function Invoke-HeadlessScan {
    $session = Initialize-DrmSession -Root $Root -DryRun:$DryRun -Console
    $catalog = Get-DrmCatalog -Path $CatalogPath
    $scan = Invoke-DrmScan -Catalog $catalog
    $upd = $null
    if ($CheckUpdates) { $upd = Invoke-DrmUpdateCheck -OemProfile $scan.OemProfile -Devices $scan.Devices }
    $report = New-DrmReport -Title 'รายงานการตรวจระบบ' -System $scan.System -Devices $scan.Devices -Runtimes $scan.Runtimes -Checks $scan.Checks -WuDrivers $(if ($upd) { $upd.WindowsUpdate } else { @() }) -OemScan $(if ($upd) { $upd.OemScan } else { $null })
    Write-Host ''
    Write-Host '=== ผลตรวจความเข้ากันได้ ===' -ForegroundColor Cyan
    $scan.Checks | Format-Table Area, Check, Status, Detail -AutoSize -Wrap | Out-String -Width 220 | Write-Host
    Write-Host ("รายงาน HTML: {0}" -f $report.Html) -ForegroundColor Green
    Write-Host ("รายงาน JSON: {0}" -f $report.Json) -ForegroundColor Green
    Write-Host ("Log: {0}" -f $session.LogFile) -ForegroundColor Green
    return 0
}

function Invoke-HeadlessInstall {
    $session = Initialize-DrmSession -Root $Root -DryRun:$DryRun -Console
    $catalog = Get-DrmCatalog -Path $CatalogPath
    Set-DrmCatalogCached $catalog
    if ($Resume) {
        $state = Read-DrmResumeState -Root $session.Root
        if (-not $state) { Write-Host 'ไม่พบงานค้างให้ทำต่อ' -ForegroundColor Yellow; return 0 }
        Write-DrmLog ("ทำงานต่อจากเซสชัน {0} (รอบที่ {1}) อีก {2} รายการ" -f $state.SessionId, $state.Attempt, @($state.Items).Count) -Level Step
        $sum = Invoke-DrmInstallPlan -Plan @($state.Items) -Options $state.Options -Catalog $catalog -Snapshot $state.Snapshot -ResumeAttempt ([int]$state.Attempt) -LauncherPath $LauncherPath
        return $(if ($sum.Failed) { 1 } else { 0 })
    }
    $scan = Invoke-DrmScan -Catalog $catalog
    $planItems = New-Object System.Collections.Generic.List[object]
    if ($IncludeOem -and $scan.OemProfile.Vendor -ne 'Other') { $planItems.Add((New-DrmPlanItemFromOem -OemProfile $scan.OemProfile)) }
    foreach ($f in $Files) {
        foreach ($info in (Get-DrmInstallerInfo -Path $f -Catalog $catalog)) {
            if ($info.Kind -eq 'Unknown') { Write-DrmLog ("ข้ามไฟล์ที่ไม่รู้จักชนิด: {0}" -f $info.Path) -Level Warn; continue }
            $planItems.Add((New-DrmPlanItemFromLocal -Info $info))
        }
    }
    if ($IncludeWindowsUpdateDrivers) {
        $wuList = Find-DrmWindowsUpdateDrivers -Devices $scan.Devices
        foreach ($w in @($wuList | Where-Object { $_.Selected })) { $planItems.Add((New-DrmPlanItemFromWindowsUpdate -Driver $w)) }
    }
    foreach ($r in (Select-DrmRuntimeByPreset -Runtimes $scan.Runtimes -Preset $Preset -Ids $Items)) { $planItems.Add((New-DrmPlanItemFromRuntime -Runtime $r)) }
    if ($planItems.Count -eq 0) { Write-Host 'ไม่มีรายการให้ติดตั้ง' -ForegroundColor Yellow; return 0 }
    $plan = New-DrmPlan -Items $planItems.ToArray()
    Write-Host ''
    Write-Host '=== ลำดับการติดตั้ง ===' -ForegroundColor Cyan
    $plan | Format-Table Sequence, PhaseName, Name -AutoSize | Out-String -Width 200 | Write-Host
    $sum = Invoke-DrmInstallPlan -Plan $plan -Options (Get-RunOptions) -Catalog $catalog -System $scan.System -DevicesBefore $scan.Devices -OemProfile $scan.OemProfile -LauncherPath $LauncherPath
    if ($sum.Checks) { $sum.Checks | Format-Table Area, Check, Status, Detail -AutoSize -Wrap | Out-String -Width 220 | Write-Host }
    if ($sum.Report) { Write-Host ("รายงาน: {0}" -f $sum.Report.Html) -ForegroundColor Green }
    return $(if ($sum.Failed) { 1 } else { 0 })
}

# ---------------------------------------------------------------------------
# หน้าต่าง (XAML)
# ---------------------------------------------------------------------------
$script:Xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Driver &amp; Runtime Manager — ตัวจัดการไดรเวอร์และรันไทม์"
        Width="1240" Height="800" MinWidth="960" MinHeight="620"
        WindowStartupLocation="CenterScreen" FontFamily="Leelawadee UI, Segoe UI" FontSize="13" Background="#F4F6F9">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Padding" Value="12,5"/>
      <Setter Property="Margin" Value="0,0,6,0"/>
      <Setter Property="MinWidth" Value="80"/>
    </Style>
    <Style x:Key="Primary" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Background" Value="#1F4E79"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>
    <Style TargetType="CheckBox"><Setter Property="Margin" Value="0,0,14,0"/><Setter Property="VerticalAlignment" Value="Center"/></Style>
    <Style TargetType="DataGrid">
      <Setter Property="AutoGenerateColumns" Value="False"/>
      <Setter Property="CanUserAddRows" Value="False"/>
      <Setter Property="CanUserDeleteRows" Value="False"/>
      <Setter Property="HeadersVisibility" Value="Column"/>
      <Setter Property="GridLinesVisibility" Value="Horizontal"/>
      <Setter Property="HorizontalGridLinesBrush" Value="#E3E8EE"/>
      <Setter Property="RowHeaderWidth" Value="0"/>
      <Setter Property="Background" Value="White"/>
      <Setter Property="BorderBrush" Value="#D5DCE4"/>
      <Setter Property="AlternationCount" Value="2"/>
      <Setter Property="EnableRowVirtualization" Value="True"/>
    </Style>
    <Style TargetType="DataGridRow">
      <Style.Triggers>
        <DataTrigger Binding="{Binding Level}" Value="error"><Setter Property="Background" Value="#FDECEA"/></DataTrigger>
        <DataTrigger Binding="{Binding Level}" Value="warn"><Setter Property="Background" Value="#FFF8E1"/></DataTrigger>
        <DataTrigger Binding="{Binding Level}" Value="ok"><Setter Property="Background" Value="#EAF6EC"/></DataTrigger>
      </Style.Triggers>
    </Style>
    <DataTemplate x:Key="SelectCell">
      <CheckBox IsChecked="{Binding Selected, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}" IsEnabled="{Binding Enabled}" HorizontalAlignment="Center" Margin="0"/>
    </DataTemplate>
  </Window.Resources>
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <Border Grid.Row="0" Background="#1F4E79" Padding="16,10">
      <DockPanel LastChildFill="True">
        <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
          <Button x:Name="BtnScan" Content="สแกนระบบใหม่"/>
          <Button x:Name="BtnCheck" Content="ตรวจหาอัปเดต"/>
          <Button x:Name="BtnReport" Content="บันทึกรายงาน"/>
        </StackPanel>
        <StackPanel>
          <TextBlock Text="ตัวจัดการไดรเวอร์และรันไทม์" Foreground="White" FontSize="19" FontWeight="SemiBold"/>
          <TextBlock x:Name="TxtMachine" Text="กำลังเตรียมตรวจระบบ..." Foreground="#D6E4F0" TextTrimming="CharacterEllipsis"/>
        </StackPanel>
      </DockPanel>
    </Border>

    <TabControl x:Name="Tabs" Grid.Row="1" Margin="10,10,10,6">
      <TabItem Header="1. ตรวจระบบ">
        <Grid Margin="6">
          <Grid.RowDefinitions><RowDefinition Height="2*"/><RowDefinition Height="5"/><RowDefinition Height="*"/></Grid.RowDefinitions>
          <DataGrid x:Name="SysGrid" Grid.Row="0" IsReadOnly="True">
            <DataGrid.Columns>
              <DataGridTextColumn Header="หมวด" Binding="{Binding Group}" Width="120"/>
              <DataGridTextColumn Header="หัวข้อ" Binding="{Binding Name}" Width="230"/>
              <DataGridTextColumn Header="ค่า / ผลตรวจ" Binding="{Binding Note}" Width="*"/>
            </DataGrid.Columns>
          </DataGrid>
          <GridSplitter Grid.Row="1" Height="5" HorizontalAlignment="Stretch" Background="#D5DCE4"/>
          <DataGrid x:Name="CheckGrid" Grid.Row="2" IsReadOnly="True">
            <DataGrid.Columns>
              <DataGridTextColumn Header="ความเข้ากันได้: หมวด" Binding="{Binding Group}" Width="150"/>
              <DataGridTextColumn Header="รายการตรวจ" Binding="{Binding Name}" Width="260"/>
              <DataGridTextColumn Header="ผล" Binding="{Binding Status}" Width="70"/>
              <DataGridTextColumn Header="รายละเอียด" Binding="{Binding Note}" Width="*"/>
            </DataGrid.Columns>
          </DataGrid>
        </Grid>
      </TabItem>

      <TabItem Header="2. ไดรเวอร์และอัปเดต">
        <Grid Margin="6">
          <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="5"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
          <DockPanel Grid.Row="0" Margin="0,0,0,6">
            <TextBlock Text="อุปกรณ์และชุดไดรเวอร์ทั้งหมด" FontWeight="SemiBold" VerticalAlignment="Center" Margin="0,0,12,0"/>
            <ComboBox x:Name="DevFilter" Width="300" Margin="0,0,8,0">
              <ComboBoxItem Content="ไดรเวอร์ของผู้ผลิต + อุปกรณ์ที่มีปัญหา" IsSelected="True"/>
              <ComboBoxItem Content="อุปกรณ์ทั้งหมด"/>
              <ComboBoxItem Content="เฉพาะที่มีปัญหา / ไม่มีไดรเวอร์"/>
              <ComboBoxItem Content="เฉพาะที่ไม่ใช่ WHQL"/>
            </ComboBox>
            <TextBlock Text="ค้นหา:" VerticalAlignment="Center" Margin="0,0,4,0"/>
            <TextBox x:Name="DevSearch" Width="220" VerticalContentAlignment="Center"/>
            <TextBlock x:Name="TxtDevCount" VerticalAlignment="Center" Margin="12,0,0,0" Foreground="#4A5A6A"/>
          </DockPanel>
          <DataGrid x:Name="DevGrid" Grid.Row="1" IsReadOnly="True">
            <DataGrid.Columns>
              <DataGridTextColumn Header="ลำดับติดตั้ง" Binding="{Binding Group}" Width="150"/>
              <DataGridTextColumn Header="อุปกรณ์" Binding="{Binding Name}" Width="2*"/>
              <DataGridTextColumn Header="คลาส" Binding="{Binding ClassName}" Width="100"/>
              <DataGridTextColumn Header="ผู้ให้ไดรเวอร์" Binding="{Binding Vendor}" Width="140"/>
              <DataGridTextColumn Header="เวอร์ชัน" Binding="{Binding Installed}" Width="120"/>
              <DataGridTextColumn Header="วันที่" Binding="{Binding Date}" Width="85"/>
              <DataGridTextColumn Header="การรับรอง" Binding="{Binding Cert}" Width="200"/>
              <DataGridTextColumn Header="สถานะ" Binding="{Binding Status}" Width="1.2*"/>
            </DataGrid.Columns>
          </DataGrid>
          <GridSplitter Grid.Row="2" Height="5" HorizontalAlignment="Stretch" Background="#D5DCE4"/>
          <DockPanel Grid.Row="3" Margin="0,6,0,6">
            <TextBlock Text="อัปเดตไดรเวอร์ (ลำดับ: ผู้ผลิตเครื่องก่อน → ผู้ผลิตชิ้นส่วน → Windows Update ที่ Microsoft รับรองและใหม่กว่า)" FontWeight="SemiBold" VerticalAlignment="Center"/>
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
              <Button x:Name="BtnUpdRecommended" Content="เลือกที่แนะนำ"/>
              <Button x:Name="BtnUpdAll" Content="เลือกทั้งหมด"/>
              <Button x:Name="BtnUpdNone" Content="ไม่เลือก"/>
            </StackPanel>
          </DockPanel>
          <DataGrid x:Name="UpdGrid" Grid.Row="4">
            <DataGrid.Columns>
              <DataGridTemplateColumn Header="เลือก" Width="50" CellTemplate="{StaticResource SelectCell}"/>
              <DataGridTextColumn Header="แหล่ง" Binding="{Binding Source}" Width="170" IsReadOnly="True"/>
              <DataGridTextColumn Header="รายการ" Binding="{Binding Name}" Width="2*" IsReadOnly="True"/>
              <DataGridTextColumn Header="อุปกรณ์ / คลาส" Binding="{Binding ClassName}" Width="1.2*" IsReadOnly="True"/>
              <DataGridTextColumn Header="ติดตั้งอยู่" Binding="{Binding Installed}" Width="110" IsReadOnly="True"/>
              <DataGridTextColumn Header="รุ่นใหม่" Binding="{Binding Available}" Width="110" IsReadOnly="True"/>
              <DataGridTextColumn Header="เทียบ" Binding="{Binding Comparison}" Width="150" IsReadOnly="True"/>
              <DataGridTextColumn Header="สถานะ" Binding="{Binding Status}" Width="1.3*" IsReadOnly="True"/>
            </DataGrid.Columns>
          </DataGrid>
        </Grid>
      </TabItem>

      <TabItem Header="3. รันไทม์และโปรแกรมเสริม">
        <Grid Margin="6">
          <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
          <DockPanel Grid.Row="0" Margin="0,0,0,6">
            <TextBlock Text="ชุดที่เลือก:" VerticalAlignment="Center" Margin="0,0,8,0" FontWeight="SemiBold"/>
            <Button x:Name="BtnPresetRecommended" Content="แนะนำ"/>
            <Button x:Name="BtnPresetGaming" Content="เล่นเกม"/>
            <Button x:Name="BtnPresetWork" Content="ทำงาน"/>
            <Button x:Name="BtnPresetAll" Content="ทั้งหมด"/>
            <Button x:Name="BtnPresetNone" Content="ไม่เลือก"/>
            <TextBlock Text="รายการที่ติดตั้งแล้วจะตรวจรุ่นล่าสุดจากผู้ผลิต และอัปเดตเฉพาะเมื่อมีรุ่นใหม่กว่า" VerticalAlignment="Center" Foreground="#4A5A6A" Margin="10,0,0,0" TextTrimming="CharacterEllipsis"/>
          </DockPanel>
          <DataGrid x:Name="RtGrid" Grid.Row="1" VirtualizingPanel.IsVirtualizingWhenGrouping="True">
            <DataGrid.GroupStyle>
              <GroupStyle>
                <GroupStyle.HeaderTemplate>
                  <DataTemplate><TextBlock Text="{Binding Name}" FontWeight="SemiBold" Foreground="#1F4E79" Margin="4,8,0,3"/></DataTemplate>
                </GroupStyle.HeaderTemplate>
              </GroupStyle>
            </DataGrid.GroupStyle>
            <DataGrid.Columns>
              <DataGridTemplateColumn Header="เลือก" Width="50" CellTemplate="{StaticResource SelectCell}"/>
              <DataGridTextColumn Header="รายการ" Binding="{Binding Name}" Width="2*" IsReadOnly="True"/>
              <DataGridTextColumn Header="สถานะในเครื่อง" Binding="{Binding Comparison}" Width="110" IsReadOnly="True"/>
              <DataGridTextColumn Header="ติดตั้งอยู่" Binding="{Binding Installed}" Width="130" IsReadOnly="True"/>
              <DataGridTextColumn Header="ล่าสุดที่ทราบ" Binding="{Binding Available}" Width="100" IsReadOnly="True"/>
              <DataGridTextColumn Header="แหล่งดาวน์โหลด" Binding="{Binding Source}" Width="1.2*" IsReadOnly="True"/>
              <DataGridTextColumn Header="ผลติดตั้ง" Binding="{Binding Status}" Width="1.1*" IsReadOnly="True"/>
              <DataGridTextColumn Header="หมายเหตุ" Binding="{Binding Note}" Width="1.6*" IsReadOnly="True"/>
            </DataGrid.Columns>
          </DataGrid>
        </Grid>
      </TabItem>

      <TabItem Header="4. ติดตั้งจากไฟล์">
        <Grid Margin="6">
          <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
          <DockPanel Grid.Row="0" Margin="0,0,0,6">
            <Button x:Name="BtnAddFiles" Content="เพิ่มไฟล์..."/>
            <Button x:Name="BtnAddFolder" Content="เพิ่มโฟลเดอร์..."/>
            <Button x:Name="BtnRemoveFiles" Content="ลบแถวที่เลือก"/>
            <TextBlock Text="ลากไฟล์มาวางในตารางได้ — รองรับ .inf .exe .msi .msp .msu .cab .msix/.appx .zip .7z .rar .iso .vhd .bat .cmd .ps1 .reg .ppkg" VerticalAlignment="Center" Foreground="#4A5A6A" Margin="8,0,0,0" TextTrimming="CharacterEllipsis"/>
          </DockPanel>
          <DataGrid x:Name="FileGrid" Grid.Row="1" AllowDrop="True">
            <DataGrid.Columns>
              <DataGridTemplateColumn Header="เลือก" Width="50" CellTemplate="{StaticResource SelectCell}"/>
              <DataGridTextColumn Header="ลำดับติดตั้ง" Binding="{Binding Group}" Width="150" IsReadOnly="True"/>
              <DataGridTextColumn Header="ไฟล์" Binding="{Binding Name}" Width="1.5*" IsReadOnly="True"/>
              <DataGridTextColumn Header="ชนิด" Binding="{Binding Kind}" Width="140" IsReadOnly="True"/>
              <DataGridTextColumn Header="ตัวติดตั้ง/วิธี" Binding="{Binding Engine}" Width="150" IsReadOnly="True"/>
              <DataGridTextColumn Header="ตัวเลือก (แก้ได้)" Binding="{Binding Args, Mode=TwoWay, UpdateSourceTrigger=LostFocus}" Width="190"/>
              <DataGridTextColumn Header="ลายเซ็น / การรับรอง" Binding="{Binding Cert}" Width="1.3*" IsReadOnly="True"/>
              <DataGridTextColumn Header="สถานะ" Binding="{Binding Status}" Width="1.1*" IsReadOnly="True"/>
            </DataGrid.Columns>
          </DataGrid>
          <TextBlock Grid.Row="2" Margin="0,6,0,0" TextWrapping="Wrap" Foreground="#4A5A6A"
                     Text="ไฟล์จะติดตั้งตามลำดับที่ผู้ผลิตแนะนำ (BIOS → ชิปเซ็ต → Management Engine → Storage → กราฟิก → เสียง → เครือข่าย → อื่น ๆ) ไฟล์บีบอัด/ISO จะแตกหรือเมานต์แล้วติดตั้งตัวที่พบ ไฟล์ที่ไม่มีลายเซ็นจะไม่ถูกเลือกให้อัตโนมัติ ตัวติดตั้งที่ไม่รู้จักจะเปิดหน้าต่างของผู้ผลิตให้กดเอง"/>
        </Grid>
      </TabItem>

      <TabItem Header="5. ทำความสะอาด">
        <StackPanel Margin="14">
          <TextBlock Text="หลังติดตั้งเสร็จ จะลบเฉพาะไฟล์ที่ถูกสร้างระหว่างการติดตั้งรอบนี้" FontWeight="SemiBold" Margin="0,0,0,10"/>
          <CheckBox x:Name="ChkCleanWork" Content="ลบไฟล์ดาวน์โหลดและไฟล์ที่แตกของโปรแกรมนี้" IsChecked="True" Margin="0,4"/>
          <CheckBox x:Name="ChkCleanVendor" Content="ลบโฟลเดอร์แตกไฟล์ของผู้ผลิตที่สร้างใหม่ระหว่างติดตั้ง (C:\NVIDIA, C:\AMD, C:\Intel, C:\SWSetup, C:\DRIVERS ...)" IsChecked="True" Margin="0,4"/>
          <CheckBox x:Name="ChkCleanTemp" Content="ลบไฟล์ชั่วคราว (TEMP) ที่ถูกสร้างระหว่างติดตั้ง (ข้ามไฟล์ที่กำลังใช้งาน)" IsChecked="True" Margin="0,4"/>
          <CheckBox x:Name="ChkCleanWu" Content="ลบแคชดาวน์โหลดของ Windows Update ที่เกิดขึ้นรอบนี้" IsChecked="False" Margin="0,4"/>
          <StackPanel Orientation="Horizontal" Margin="0,4">
            <CheckBox x:Name="ChkRemoveOld" Content="ลบแพ็กเกจไดรเวอร์รุ่นเก่าที่มีรุ่นใหม่กว่าแล้วและไม่ได้ใช้งาน" IsChecked="False"/>
            <TextBlock x:Name="TxtOldCount" Foreground="#4A5A6A" VerticalAlignment="Center"/>
          </StackPanel>
          <CheckBox x:Name="ChkComponent" Content="ล้าง Component Store ของ Windows (DISM /StartComponentCleanup — ใช้เวลานาน)" IsChecked="False" Margin="0,4"/>
          <TextBlock Margin="0,16,0,0" TextWrapping="Wrap" Foreground="#4A5A6A"
                     Text="ความปลอดภัย: ก่อนติดตั้งจะสร้างจุดคืนค่าระบบ (System Restore) เลือกสำรองไดรเวอร์เดิมได้ที่แถบด้านล่าง การลบแพ็กเกจไดรเวอร์เก่าไม่ใช้ /force ระบบจะปฏิเสธเองถ้ายังมีอุปกรณ์ใช้อยู่"/>
        </StackPanel>
      </TabItem>

      <TabItem Header="6. บันทึก (Log)">
        <Grid Margin="6">
          <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
          <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,6">
            <Button x:Name="BtnOpenLogs" Content="เปิดโฟลเดอร์ Log/รายงาน"/>
            <Button x:Name="BtnOpenReport" Content="เปิดรายงานล่าสุด"/>
            <TextBlock x:Name="TxtLogPath" VerticalAlignment="Center" Foreground="#4A5A6A" Margin="8,0,0,0"/>
          </StackPanel>
          <TextBox x:Name="LogBox" Grid.Row="1" IsReadOnly="True" FontFamily="Consolas, Leelawadee UI" FontSize="12" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" TextWrapping="NoWrap" Background="#0F1720" Foreground="#D7E3EE"/>
        </Grid>
      </TabItem>
    </TabControl>

    <Border Grid.Row="2" Background="White" BorderBrush="#D5DCE4" BorderThickness="0,1,0,0" Padding="12,8">
      <DockPanel>
        <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
          <Button x:Name="BtnInstall" Content="▶ ติดตั้งที่เลือก" Style="{StaticResource Primary}" MinWidth="150"/>
          <Button x:Name="BtnStop" Content="■ หยุด" IsEnabled="False"/>
        </StackPanel>
        <WrapPanel VerticalAlignment="Center">
          <CheckBox x:Name="ChkRestorePoint" Content="สร้างจุดคืนค่าก่อนติดตั้ง" IsChecked="True"/>
          <CheckBox x:Name="ChkBackup" Content="สำรองไดรเวอร์เดิม" IsChecked="False"/>
          <CheckBox x:Name="ChkResume" Content="รีสตาร์ทหลัง BIOS/ชิปเซ็ตแล้วทำต่ออัตโนมัติ" IsChecked="True"/>
          <CheckBox x:Name="ChkReboot" Content="รีสตาร์ทเมื่อเสร็จ" IsChecked="False"/>
          <CheckBox x:Name="ChkUnsigned" Content="อนุญาตไฟล์ที่ไม่มีลายเซ็น" IsChecked="False"/>
          <CheckBox x:Name="ChkDryRun" Content="โหมดทดลอง (ไม่ติดตั้งจริง)" IsChecked="False"/>
        </WrapPanel>
      </DockPanel>
    </Border>

    <Border Grid.Row="3" Background="#E9EEF4" Padding="12,5">
      <DockPanel>
        <TextBlock x:Name="TxtSummary" DockPanel.Dock="Right" Foreground="#1F4E79" FontWeight="SemiBold" Margin="10,0,0,0"/>
        <ProgressBar x:Name="Progress" DockPanel.Dock="Right" Width="260" Height="14" Minimum="0" Maximum="100" Margin="10,0,0,0"/>
        <TextBlock x:Name="TxtStatus" Text="พร้อม" TextTrimming="CharacterEllipsis" VerticalAlignment="Center"/>
      </DockPanel>
    </Border>
  </Grid>
</Window>
'@

$script:ControlNames = @(
    'BtnScan', 'BtnCheck', 'BtnReport', 'TxtMachine', 'Tabs', 'SysGrid', 'CheckGrid', 'DevFilter', 'DevSearch', 'TxtDevCount', 'DevGrid',
    'BtnUpdRecommended', 'BtnUpdAll', 'BtnUpdNone', 'UpdGrid', 'BtnPresetRecommended', 'BtnPresetGaming', 'BtnPresetWork', 'BtnPresetAll',
    'BtnPresetNone', 'RtGrid', 'BtnAddFiles', 'BtnAddFolder', 'BtnRemoveFiles', 'FileGrid', 'ChkCleanWork', 'ChkCleanVendor', 'ChkCleanTemp',
    'ChkCleanWu', 'ChkRemoveOld', 'TxtOldCount', 'ChkComponent', 'BtnOpenLogs', 'BtnOpenReport', 'TxtLogPath', 'LogBox', 'BtnInstall', 'BtnStop',
    'ChkRestorePoint', 'ChkBackup', 'ChkResume', 'ChkReboot', 'ChkUnsigned', 'ChkDryRun', 'TxtSummary', 'Progress', 'TxtStatus'
)

$script:GridItemCode = @'
using System.ComponentModel;
namespace DrmGui {
    public class GridItem : INotifyPropertyChanged {
        public event PropertyChangedEventHandler PropertyChanged;
        protected void Raise(string name) { PropertyChangedEventHandler h = PropertyChanged; if (h != null) h(this, new PropertyChangedEventArgs(name)); }
        private bool _selected; public bool Selected { get { return _selected; } set { if (_selected != value) { _selected = value; Raise("Selected"); } } }
        private bool _enabled = true; public bool Enabled { get { return _enabled; } set { if (_enabled != value) { _enabled = value; Raise("Enabled"); } } }
        private int _order; public int Order { get { return _order; } set { _order = value; Raise("Order"); } }
        public object Data { get; set; }
__PROPS__
    }
}
'@

function Initialize-GridItemType {
    if ('DrmGui.GridItem' -as [type]) { return }
    $props = 'Id', 'Kind', 'Source', 'Group', 'Name', 'ClassName', 'Vendor', 'Installed', 'Available', 'Date', 'Comparison', 'Cert', 'Status', 'Note', 'Args', 'Path', 'Detail', 'Engine', 'Level'
    $sb = New-Object System.Text.StringBuilder
    foreach ($p in $props) {
        [void]$sb.AppendFormat('        private string _{0} = ""; public string {0} {{ get {{ return _{0}; }} set {{ if (_{0} != value) {{ _{0} = value; Raise("{0}"); }} }} }}', $p).AppendLine()
    }
    Add-Type -TypeDefinition ($script:GridItemCode.Replace('__PROPS__', $sb.ToString())) -Language CSharp
}

function New-GridItem {
    param([hashtable]$Values)
    $g = New-Object DrmGui.GridItem
    foreach ($k in $Values.Keys) {
        $v = $Values[$k]
        if ($k -in 'Selected', 'Enabled') { $g.$k = [bool]$v }
        elseif ($k -eq 'Order') { $g.$k = [int]$v }
        elseif ($k -eq 'Data') { $g.Data = $v }
        else { $g.$k = [string]$v }
    }
    return $g
}

function New-DrmWindow {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms
    Initialize-GridItemType
    [xml]$xml = $script:Xaml
    $reader = New-Object System.Xml.XmlNodeReader $xml
    $window = [Windows.Markup.XamlReader]::Load($reader)
    $ui = @{ Window = $window }
    foreach ($n in $script:ControlNames) {
        $c = $window.FindName($n)
        if (-not $c) { throw "ไม่พบตัวควบคุม $n ใน XAML" }
        $ui[$n] = $c
    }
    return $ui
}

# ---------------------------------------------------------------------------
# SelfTest
# ---------------------------------------------------------------------------
function Invoke-SelfTest {
    $fail = 0
    $catalog = Get-DrmCatalog -Path $CatalogPath
    $errs = Test-DrmCatalog -Catalog $catalog
    if ($errs.Count) { $fail++; Write-Host 'แคตตาล็อกผิดพลาด:' -ForegroundColor Red; $errs | ForEach-Object { Write-Host "  $_" } } else { Write-Host ("แคตตาล็อกถูกต้อง ({0} รายการ, OEM {1})" -f @($catalog.items).Count, @($catalog.oemTools).Count) -ForegroundColor Green }
    $fn = @(Get-Command -Module DriverRuntimeManager).Count
    Write-Host ("โมดูลโหลดแล้ว ({0} ฟังก์ชัน)" -f $fn) -ForegroundColor Green
    if ((Test-DrmIsWindows) -and [Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
        $fail++; Write-Host 'ต้องรัน SelfTest ด้วย -STA เพื่อทดสอบหน้าต่าง WPF' -ForegroundColor Red
    }
    elseif (Test-DrmIsWindows) {
        try {
            $ui = New-DrmWindow
            $g = New-GridItem @{ Name = 'ทดสอบ'; Selected = $true; Order = 1 }
            if (-not $g.Selected) { throw 'GridItem ไม่ทำงาน' }
            $ui.Window.Close()
            Write-Host ("หน้าต่าง XAML โหลดได้ พบตัวควบคุมครบ {0} ตัว" -f $script:ControlNames.Count) -ForegroundColor Green
        } catch { $fail++; Write-Host ("โหลดหน้าต่างไม่ได้: {0}" -f $_.Exception.Message) -ForegroundColor Red }
    }
    else { Write-Host 'ข้ามการทดสอบหน้าต่าง (ไม่ใช่ Windows)' -ForegroundColor Yellow }
    return $fail
}

# ---------------------------------------------------------------------------
# GUI
# ---------------------------------------------------------------------------
$script:WorkerHeader = @'
param($ModulePath, $Session, $Queue, $Sync, $DryRun, $P)
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
Import-Module $ModulePath -Force -DisableNameChecking
Use-DrmSession -Session $Session -Queue $Queue -Sync $Sync -DryRun:$DryRun
try {
'@
$script:WorkerFooter = @'
} catch {
    Write-DrmLog ("เกิดข้อผิดพลาด: {0}" -f $_.Exception.Message) -Level Error
    Send-DrmEvent -Type 'WorkerError' -Data @{ Message = $_.Exception.Message }
}
'@

$script:ScanBody = @'
$cat = Get-DrmCatalog -Path $P.CatalogPath
$scan = Invoke-DrmScan -Catalog $cat
Send-DrmEvent -Type 'ScanResult' -Data @{ Scan = $scan }
if ($P.AutoCheck) {
    $upd = Invoke-DrmUpdateCheck -OemProfile $scan.OemProfile -Devices $scan.Devices
    Send-DrmEvent -Type 'UpdateResult' -Data @{ Update = $upd }
}
'@
$script:UpdateBody = @'
$upd = Invoke-DrmUpdateCheck -OemProfile $P.OemProfile -Devices $P.Devices
Send-DrmEvent -Type 'UpdateResult' -Data @{ Update = $upd }
'@
$script:InstallBody = @'
$cat = Get-DrmCatalog -Path $P.CatalogPath
$sum = Invoke-DrmInstallPlan -Plan $P.Plan -Options $P.Options -Catalog $cat -System $P.System -DevicesBefore $P.Devices -OemProfile $P.OemProfile -Snapshot $P.Snapshot -ResumeAttempt $P.ResumeAttempt -LauncherPath $P.LauncherPath
Send-DrmEvent -Type 'InstallResult' -Data @{ Summary = $sum }
'@
$script:FilesBody = @'
$cat = Get-DrmCatalog -Path $P.CatalogPath
foreach ($path in $P.Paths) {
    Write-DrmLog ("วิเคราะห์ไฟล์: {0}" -f $path)
    $infos = Get-DrmInstallerInfo -Path $path -Catalog $cat
    if ($infos.Count -eq 0) { Write-DrmLog ("ไม่พบไฟล์ที่ติดตั้งได้ใน {0}" -f $path) -Level Warn }
    Send-DrmEvent -Type 'FileInfo' -Data @{ Infos = $infos }
}
'@

function Start-UiWorker {
    param([string]$Slot = 'main', [string]$Body, [hashtable]$Params = @{}, [switch]$DryRunMode)
    if ($script:Workers[$Slot]) { return $false }
    $script:Sync.Cancel = $false
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'
    $rs.ThreadOptions = 'ReuseThread'
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($script:WorkerHeader + "`n" + $Body + "`n" + $script:WorkerFooter)
    [void]$ps.AddParameters(@{ ModulePath = $ModulePath; Session = $script:Session; Queue = $script:Queue; Sync = $script:Sync; DryRun = [bool]$DryRunMode; P = $Params })
    $handle = $ps.BeginInvoke()
    $script:Workers[$Slot] = @{ PS = $ps; Handle = $handle; Runspace = $rs; Started = (Get-Date) }
    Update-BusyState
    return $true
}

function Complete-UiWorkers {
    foreach ($slot in @($script:Workers.Keys)) {
        $w = $script:Workers[$slot]
        if (-not $w -or -not $w.Handle.IsCompleted) { continue }
        try { [void]$w.PS.EndInvoke($w.Handle) } catch { Add-UiLog ("[ERROR] {0}" -f $_.Exception.Message) }
        foreach ($e in $w.PS.Streams.Error) { Add-UiLog ("[ERROR] {0}" -f $e) }
        $w.PS.Dispose(); $w.Runspace.Dispose()
        $script:Workers.Remove($slot)
        Update-BusyState
        if ($slot -eq 'main' -and $script:PendingRescan) { $script:PendingRescan = $false; Start-UiScan }
    }
}

function Test-UiBusy { return [bool]$script:Workers['main'] }

function Update-BusyState {
    $busy = Test-UiBusy
    foreach ($n in 'BtnScan', 'BtnCheck', 'BtnInstall') { $script:Ui[$n].IsEnabled = -not $busy }
    $script:Ui.BtnStop.IsEnabled = $busy
    if (-not $busy) { $script:Ui.Progress.IsIndeterminate = $false }
}

function Add-UiLog {
    param([string]$Text)
    $box = $script:Ui.LogBox
    $box.AppendText($Text + [Environment]::NewLine)
    if ($box.Text.Length -gt 600000) { $box.Text = $box.Text.Substring($box.Text.Length - 400000) }
    $box.ScrollToEnd()
}

function Get-AllGridCollections { @($script:Updates, $script:Runtimes, $script:FilesCol) }

function Find-UiItem {
    param([string]$Id)
    foreach ($c in Get-AllGridCollections) { foreach ($i in $c) { if ($i.Id -eq $Id) { return $i } } }
    return $null
}

function Set-UiMachineText {
    $s = $script:Scan.System
    $script:Ui.TxtMachine.Text = ('{0} {1} | {2} {3} (บิลด์ {4}.{5}) {6} | {7}' -f $s.Hardware.Manufacturer, $s.Hardware.Model, $s.OS.Caption, $s.OS.DisplayVersion, $s.OS.Build, $s.OS.UBR, $s.OS.Architecture, $(if ($s.IsAdmin) { 'สิทธิ์ Administrator' } else { 'ไม่มีสิทธิ์ Administrator' }))
}

function Update-DeviceFilter {
    $view = [Windows.Data.CollectionViewSource]::GetDefaultView($script:Devices)
    if (-not $view) { return }
    $mode = $script:Ui.DevFilter.SelectedIndex
    $q = ([string]$script:Ui.DevSearch.Text).Trim()
    $view.Filter = [Predicate[object]] {
        param($o)
        $d = $o.Data
        $okMode = switch ($mode) {
            1 { $true }
            2 { $d.ProblemCode -ne 0 -and $d.ProblemCode -ne 22 }
            3 { $d.CertLevel -notin 'WHQL', 'Inbox', 'None' }
            default { ($d.CertLevel -ne 'Inbox' -and $d.CertLevel -ne 'None') -or ($d.ProblemCode -ne 0 -and $d.ProblemCode -ne 22) }
        }
        if (-not $okMode) { return $false }
        if ($q) { return ($o.Name -like "*$q*" -or $o.Vendor -like "*$q*" -or $o.ClassName -like "*$q*" -or $o.Installed -like "*$q*") }
        return $true
    }.GetNewClosure()
    $shown = 0; foreach ($x in $view) { $shown++ }
    $script:Ui.TxtDevCount.Text = ('แสดง {0} จาก {1} อุปกรณ์' -f $shown, $script:Devices.Count)
}

function Show-ScanResult {
    param($Scan)
    $script:Scan = $Scan
    Set-UiMachineText
    $script:SysRows.Clear()
    foreach ($r in $Scan.SystemRows) { $script:SysRows.Add((New-GridItem @{ Group = $r.Section; Name = $r.Item; Note = $r.Value; Level = $r.Level })) }
    Show-Checks $Scan.Checks
    $script:Devices.Clear()
    foreach ($d in $Scan.Devices) {
        $lvl = $d.Level
        $status = if ($d.ProblemText) { $d.ProblemText } elseif (-not $d.Present) { 'ไม่ได้เชื่อมต่อ' } else { 'ปกติ' }
        $script:Devices.Add((New-GridItem @{ Id = $d.DeviceId; Group = $d.OrderGroup; Name = $d.Name; ClassName = $d.Class; Vendor = $(if ($d.DriverProvider) { $d.DriverProvider } else { $d.VendorName }); Installed = $d.DriverVersion; Date = $d.DriverDate; Cert = $d.CertText; Status = $status; Level = $lvl; Data = $d }))
    }
    Update-DeviceFilter
    # รายการอัปเดตจากผู้ผลิต (OEM/ชิ้นส่วน) — Windows Update จะเพิ่มหลังตรวจหาอัปเดต
    $keepWu = @($script:Updates | Where-Object { $_.Kind -eq 'WuDriver' })
    $script:Updates.Clear()
    $oem = $Scan.OemProfile
    if ($oem.Vendor -ne 'Other') {
        $script:Updates.Add((New-GridItem @{ Id = 'oem'; Kind = 'OemTool'; Source = ('1) ผู้ผลิตเครื่อง: ' + $oem.Vendor); Name = $oem.Name; ClassName = 'BIOS ชิปเซ็ต ไดรเวอร์ เฟิร์มแวร์'; Comparison = $(if ($oem.Automated) { 'อัตโนมัติตามลำดับของผู้ผลิต' } else { 'เปิดเครื่องมือ/หน้าเว็บผู้ผลิต' }); Status = $oem.Note; Selected = [bool]$oem.Automated; Order = 1; Data = $oem }))
    }
    foreach ($v in $Scan.VendorTools) {
        $script:Updates.Add((New-GridItem @{ Id = ('vendor:' + $v.Vendor); Kind = 'VendorTool'; Source = ('2) ผู้ผลิตชิ้นส่วน: ' + $v.Vendor); Name = $v.Name; ClassName = (($v.Devices | Select-Object -First 2) -join '; '); Comparison = 'เครื่องมือ/หน้าดาวน์โหลดทางการ'; Status = $v.Note; Selected = [bool]$v.Default; Order = 2; Data = $v }))
    }
    foreach ($w in $keepWu) { $script:Updates.Add($w) }
    $script:Runtimes.Clear()
    foreach ($r in $Scan.Runtimes) {
        $lvl = if (-not $r.Installed) { 'warn' } elseif ($r.State -eq 'มีรุ่นใหม่กว่า') { 'warn' } else { '' }
        $script:Runtimes.Add((New-GridItem @{ Id = $r.Id; Kind = 'Catalog'; Group = $r.Group; Name = $r.Name; Comparison = $r.State; Installed = $r.InstalledVersion; Available = $r.LatestVersion; Source = $r.Source; Note = $r.Note; Level = $lvl; Order = $r.Order; Data = $r }))
    }
    Set-RuntimePreset 'recommended'
    $script:Ui.TxtOldCount.Text = $(if (@($Scan.OldPackages).Count) { '  (พบ {0} แพ็กเกจ)' -f @($Scan.OldPackages).Count } else { '  (ไม่พบ)' })
}

function Show-Checks {
    param($Checks)
    $script:CheckRows.Clear()
    foreach ($c in $Checks) {
        $lvl = switch ($c.Status) { 'ผ่าน' { 'ok' } 'เตือน' { 'warn' } 'ไม่ผ่าน' { 'error' } default { '' } }
        $script:CheckRows.Add((New-GridItem @{ Group = $c.Area; Name = $c.Check; Status = $c.Status; Note = $c.Detail; Level = $lvl }))
    }
}

function Show-UpdateResult {
    param($Update)
    $script:LastUpdate = $Update
    $oemItem = Find-UiItem 'oem'
    if ($oemItem -and $Update.OemScan) {
        $os = $Update.OemScan
        $names = (@($os.Updates) | Select-Object -First 6 | ForEach-Object { '{0} {1}' -f $_.Name, $_.Version }) -join '; '
        $oemItem.Available = $(if (@($os.Updates).Count) { '{0} รายการ' -f @($os.Updates).Count } else { '' })
        $oemItem.Status = switch ($os.Status) {
            'UpToDate' { 'ไม่มีอัปเดตใหม่จากผู้ผลิต' }
            'Found' { 'พบ: ' + $names }
            'Missing' { $os.Detail }
            default { [string]$os.Detail }
        }
        if ($os.Status -eq 'UpToDate') { $oemItem.Selected = $false; $oemItem.Level = 'ok' }
        elseif ($os.Status -eq 'Found') { $oemItem.Selected = $true; $oemItem.Level = 'warn' }
    }
    foreach ($old in @($script:Updates | Where-Object { $_.Kind -eq 'WuDriver' })) { [void]$script:Updates.Remove($old) }
    foreach ($w in @($Update.WindowsUpdate)) {
        $lvl = if ($w.Comparison -in 'Missing', 'Newer') { 'warn' } else { '' }
        $script:Updates.Add((New-GridItem @{ Id = $w.Id; Kind = 'WuDriver'; Source = '3) Windows Update (Microsoft รับรอง)'; Name = $w.Title; ClassName = $(if ($w.DeviceName) { $w.DeviceName } else { $w.DriverClass }); Installed = $w.InstalledVersion; Available = ('{0} ({1})' -f $w.OfferedVersion, $w.OfferedDate); Comparison = $w.ComparisonText; Status = ('{0} MB' -f $w.SizeMB); Selected = [bool]$w.Selected; Level = $lvl; Order = 3; Data = $w }))
    }
    $n = @($Update.WindowsUpdate).Count
    $sel = @($Update.WindowsUpdate | Where-Object { $_.Selected }).Count
    $script:Ui.TxtStatus.Text = ('ตรวจหาอัปเดตเสร็จ: Windows Update เสนอ {0} รายการ (ใหม่กว่า/ขาด {1})' -f $n, $sel)
}

function Set-RuntimePreset {
    param([string]$Name)
    foreach ($i in $script:Runtimes) {
        $r = $i.Data
        $i.Selected = switch ($Name) { 'all' { $true } 'none' { $false } default { @($r.Presets) -contains $Name } }
    }
}

function Add-UiFileInfos {
    param($Infos)
    foreach ($info in @($Infos)) {
        if (Find-UiItem $info.Id) { continue }
        $lvl = if (-not $info.SignatureValid) { 'error' } elseif ($info.CertLevel -in 'Vendor', 'Attested') { 'warn' } else { '' }
        $engine = if (-not $info.Args -and $info.Kind -eq 'Exe') { $info.Engine + ' (เปิดหน้าต่างผู้ผลิต)' } else { $info.Engine }
        $script:FilesCol.Add((New-GridItem @{ Id = $info.Id; Kind = $info.KindText; Group = $info.OrderGroup; Name = $info.Name; Engine = $engine; Args = $info.Args; Cert = $info.SignatureText; Path = $info.Path; Selected = [bool]$info.Selected; Level = $lvl; Order = $info.OrderIndex; Data = $info; Status = 'รอติดตั้ง' }))
    }
    $view = [Windows.Data.CollectionViewSource]::GetDefaultView($script:FilesCol)
    $view.SortDescriptions.Clear()
    $view.SortDescriptions.Add((New-Object System.ComponentModel.SortDescription('Order', [System.ComponentModel.ListSortDirection]::Ascending)))
}

function Add-UiPaths {
    param([string[]]$Paths)
    $p = @($Paths | Where-Object { $_ })
    if ($p.Count -eq 0) { return }
    $script:Ui.Tabs.SelectedIndex = 3
    if (-not (Start-UiWorker -Slot 'files' -Body $script:FilesBody -Params @{ CatalogPath = $CatalogPath; Paths = $p })) {
        [void][Windows.MessageBox]::Show('กำลังวิเคราะห์ไฟล์ชุดก่อนอยู่ กรุณารอสักครู่', 'Driver & Runtime Manager')
    }
}

function Get-UiOptions {
    $u = $script:Ui
    [pscustomobject]@{
        CreateRestorePoint = [bool]$u.ChkRestorePoint.IsChecked
        BackupDrivers      = [bool]$u.ChkBackup.IsChecked
        ResumeAfterReboot  = [bool]$u.ChkResume.IsChecked
        Reboot             = [bool]$u.ChkReboot.IsChecked
        AllowUnsigned      = [bool]$u.ChkUnsigned.IsChecked
        Cleanup            = $true
        KeepDownloads      = -not [bool]$u.ChkCleanWork.IsChecked
        CleanVendorFolders = [bool]$u.ChkCleanVendor.IsChecked
        CleanTemp          = [bool]$u.ChkCleanTemp.IsChecked
        CleanWuCache       = [bool]$u.ChkCleanWu.IsChecked
        RemoveOldDrivers   = [bool]$u.ChkRemoveOld.IsChecked
        ComponentCleanup   = [bool]$u.ChkComponent.IsChecked
    }
}

function Get-UiPlanItems {
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($i in $script:Updates) {
        if (-not $i.Selected) { continue }
        switch ($i.Kind) {
            'OemTool' { $list.Add((New-DrmPlanItemFromOem -OemProfile $i.Data)) }
            'VendorTool' { $list.Add((New-DrmPlanItemFromVendor -Vendor $i.Data)) }
            'WuDriver' { $list.Add((New-DrmPlanItemFromWindowsUpdate -Driver $i.Data)) }
        }
    }
    foreach ($i in $script:FilesCol) {
        if (-not $i.Selected) { continue }
        $info = $i.Data
        $info.Args = $i.Args
        $list.Add((New-DrmPlanItemFromLocal -Info $info))
    }
    foreach ($i in $script:Runtimes) { if ($i.Selected) { $list.Add((New-DrmPlanItemFromRuntime -Runtime $i.Data)) } }
    return , $list.ToArray()
}

function Update-SelectionSummary {
    $u = @($script:Updates | Where-Object { $_.Selected }).Count
    $f = @($script:FilesCol | Where-Object { $_.Selected }).Count
    $r = @($script:Runtimes | Where-Object { $_.Selected }).Count
    $script:Ui.TxtSummary.Text = ('เลือก: ไดรเวอร์ {0} | ไฟล์ {1} | รันไทม์/โปรแกรม {2}' -f $u, $f, $r)
}

function Start-UiScan {
    param([switch]$AutoCheck)
    $script:Ui.Progress.IsIndeterminate = $false
    [void](Start-UiWorker -Slot 'main' -Body $script:ScanBody -Params @{ CatalogPath = $CatalogPath; AutoCheck = [bool]$AutoCheck })
}

function Start-UiInstall {
    param($Plan, [int]$ResumeAttempt = 0, $Options, $Snapshot)
    foreach ($p in $Plan) { $it = Find-UiItem $p.Id; if ($it) { $it.Status = 'รอคิว (' + $p.Sequence + ')' } }
    $dry = [bool]$script:Ui.ChkDryRun.IsChecked
    $params = @{
        CatalogPath = $CatalogPath; Plan = $Plan; Options = $Options; System = $(if ($script:Scan) { $script:Scan.System } else { $null })
        Devices = $(if ($script:Scan) { $script:Scan.Devices } else { @() }); OemProfile = $(if ($script:Scan) { $script:Scan.OemProfile } else { $null })
        Snapshot = $Snapshot; ResumeAttempt = $ResumeAttempt; LauncherPath = $LauncherPath
    }
    $script:Ui.Tabs.SelectedIndex = 5
    [void](Start-UiWorker -Slot 'main' -Body $script:InstallBody -Params $params -DryRunMode:$dry)
}

function Invoke-UiInstallClick {
    if (Test-UiBusy) { return }
    $items = Get-UiPlanItems
    if ($items.Count -eq 0) { [void][Windows.MessageBox]::Show('ยังไม่ได้เลือกรายการใด', 'Driver & Runtime Manager'); return }
    $plan = New-DrmPlan -Items $items
    $lines = $plan | Group-Object PhaseName | ForEach-Object { '• {0}: {1} รายการ' -f $_.Name, $_.Count }
    $dry = [bool]$script:Ui.ChkDryRun.IsChecked
    $msg = "จะดำเนินการตามลำดับต่อไปนี้:`n`n{0}`n`nรวม {1} รายการ{2}`n`nเริ่มเลยหรือไม่?" -f ($lines -join "`n"), $plan.Count, $(if ($dry) { ' (โหมดทดลอง — ไม่ติดตั้งจริง)' } else { '' })
    $ans = [Windows.MessageBox]::Show($msg, 'ยืนยันการติดตั้ง', 'YesNo', 'Question')
    if ($ans -ne 'Yes') { return }
    Start-UiInstall -Plan $plan -Options (Get-UiOptions) -Snapshot (Get-DrmCleanupSnapshot)
}

function Show-InstallResult {
    param($Summary)
    foreach ($r in @($Summary.Results)) {
        $it = Find-UiItem $r.Id
        if ($it) { $it.Status = ('{0} {1}' -f $r.Result.StatusText, $r.Result.Detail).Trim() }
    }
    if ($Summary.Resume) { $script:Ui.TxtStatus.Text = 'รอรีสตาร์ทเพื่อทำงานต่อ (ยกเลิกได้ด้วย shutdown /a)'; return }
    if ($Summary.Checks) { Show-Checks $Summary.Checks; $script:Ui.Tabs.SelectedIndex = 0 }
    if ($Summary.Report) { $script:LastReport = $Summary.Report.Html }
    $text = "ติดตั้งเสร็จ: สำเร็จ/เป็นรุ่นล่าสุด {0}, ล้มเหลว {1}`n`nรายงานละเอียด: {2}`nLog: {3}" -f $Summary.Succeeded, $Summary.Failed, $script:LastReport, $script:Session.LogFile
    if ($script:LastReport -and (Test-Path -LiteralPath $script:LastReport)) { Start-Process $script:LastReport }
    if ($Summary.RebootRequired -and -not [bool]$script:Ui.ChkReboot.IsChecked -and -not [bool]$script:Ui.ChkDryRun.IsChecked) {
        $ans = [Windows.MessageBox]::Show($text + "`n`nต้องรีสตาร์ทเพื่อให้ไดรเวอร์/รันไทม์ทำงานสมบูรณ์ — รีสตาร์ทตอนนี้หรือไม่?", 'ติดตั้งเสร็จ', 'YesNo', 'Question')
        if ($ans -eq 'Yes') { & shutdown.exe /r /t 30 /c "Driver & Runtime Manager: รีสตาร์ทเพื่อให้การติดตั้งสมบูรณ์" | Out-Null }
    }
    else { [void][Windows.MessageBox]::Show($text, 'ติดตั้งเสร็จ', 'OK', 'Information') }
    $script:PendingRescan = $true
}

function Invoke-UiMessage {
    param($m, [System.Text.StringBuilder]$Log)
    switch ($m.Type) {
        'Log' {
            [void]$Log.AppendLine($m.Text)
            if ($m.Level -in 'Step', 'Error') { $script:Ui.TxtStatus.Text = ($m.Text -replace '^\S+ \S+ \[\w+\s*\] ', '') }
        }
        'Progress' { $script:Ui.Progress.Value = [double]$m.Percent; if ($m.Text) { $script:Ui.TxtStatus.Text = $m.Text } }
        'Download' { $script:Ui.TxtStatus.Text = $m.Text; if ($m.Id) { $it = Find-UiItem $m.Id; if ($it) { $it.Status = $m.Text } } }
        'ItemStatus' {
            $it = Find-UiItem $m.Id
            if ($it) {
                $it.Status = $(if ($m.Detail) { '{0} — {1}' -f $m.Status, $m.Detail } else { $m.Status })
                if ($m.Level) { $it.Level = $m.Level }
            }
        }
        'ScanResult' { Show-ScanResult $m.Scan; $script:Ui.TxtStatus.Text = 'ตรวจระบบเสร็จ — ตรวจรายการแล้วติ๊กเลือก จากนั้นกด "ติดตั้งที่เลือก"' }
        'UpdateResult' { Show-UpdateResult $m.Update }
        'FileInfo' { Add-UiFileInfos $m.Infos }
        'InstallResult' { Show-InstallResult $m.Summary }
        'InstallCheckpoint' {
            [void][Windows.MessageBox]::Show(("ติดตั้ง BIOS/ชิปเซ็ตแล้ว ผู้ผลิตแนะนำให้รีสตาร์ทก่อนติดตั้งส่วนที่เหลือ`n`nเครื่องจะรีสตาร์ทใน 60 วินาที แล้วโปรแกรมจะเปิดขึ้นมาทำต่ออีก {0} รายการโดยอัตโนมัติ`n(ยกเลิกการรีสตาร์ทได้ด้วยคำสั่ง shutdown /a)" -f $m.Summary.Remaining), 'รีสตาร์ทตามคำแนะนำผู้ผลิต', 'OK', 'Information')
        }
        'WorkerError' { $script:Ui.TxtStatus.Text = 'ข้อผิดพลาด: ' + $m.Message }
    }
}

function Hide-ConsoleWindow {
    if ($ShowConsole) { return }
    try {
        if (-not ('DrmGui.Native' -as [type])) {
            Add-Type -Namespace DrmGui -Name Native -MemberDefinition '[DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow(); [DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);'
        }
        $h = [DrmGui.Native]::GetConsoleWindow()
        if ($h -ne [IntPtr]::Zero) { [void][DrmGui.Native]::ShowWindow($h, 0) }
    } catch { }
}

function Start-Gui {
    $script:Ui = New-DrmWindow
    $script:Queue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
    $script:Sync = [hashtable]::Synchronized(@{ Cancel = $false })
    $script:Workers = @{}
    $script:Session = Initialize-DrmSession -Root $Root -Queue $script:Queue -Sync $script:Sync
    $script:Catalog = Get-DrmCatalog -Path $CatalogPath
    Set-DrmCatalogCached $script:Catalog
    $script:Scan = $null
    $script:LastReport = $null
    $script:SysRows = New-Object 'System.Collections.ObjectModel.ObservableCollection[DrmGui.GridItem]'
    $script:CheckRows = New-Object 'System.Collections.ObjectModel.ObservableCollection[DrmGui.GridItem]'
    $script:Devices = New-Object 'System.Collections.ObjectModel.ObservableCollection[DrmGui.GridItem]'
    $script:Updates = New-Object 'System.Collections.ObjectModel.ObservableCollection[DrmGui.GridItem]'
    $script:Runtimes = New-Object 'System.Collections.ObjectModel.ObservableCollection[DrmGui.GridItem]'
    $script:FilesCol = New-Object 'System.Collections.ObjectModel.ObservableCollection[DrmGui.GridItem]'
    $u = $script:Ui
    $u.SysGrid.ItemsSource = $script:SysRows
    $u.CheckGrid.ItemsSource = $script:CheckRows
    $u.DevGrid.ItemsSource = $script:Devices
    $u.UpdGrid.ItemsSource = $script:Updates
    $u.RtGrid.ItemsSource = $script:Runtimes
    $u.FileGrid.ItemsSource = $script:FilesCol
    $rtView = [Windows.Data.CollectionViewSource]::GetDefaultView($script:Runtimes)
    $rtView.GroupDescriptions.Add((New-Object System.Windows.Data.PropertyGroupDescription('Group')))
    $u.TxtLogPath.Text = $script:Session.LogFile
    Add-UiLog ("Driver & Runtime Manager — เซสชัน {0}" -f $script:Session.Id)
    Add-UiLog ("Log: {0}" -f $script:Session.LogFile)

    $u.BtnScan.Add_Click({ Start-UiScan -AutoCheck })
    $u.BtnCheck.Add_Click({
            if (-not $script:Scan) { Start-UiScan -AutoCheck; return }
            [void](Start-UiWorker -Slot 'main' -Body $script:UpdateBody -Params @{ OemProfile = $script:Scan.OemProfile; Devices = $script:Scan.Devices })
        })
    $u.BtnReport.Add_Click({
            if (-not $script:Scan) { return }
            $wu = if ($script:LastUpdate) { $script:LastUpdate.WindowsUpdate } else { @() }
            $oemScan = if ($script:LastUpdate) { $script:LastUpdate.OemScan } else { $null }
            $r = New-DrmReport -Title 'รายงานการตรวจระบบ' -System $script:Scan.System -Devices $script:Scan.Devices -Runtimes $script:Scan.Runtimes -Checks $script:Scan.Checks -WuDrivers $wu -OemScan $oemScan
            $script:LastReport = $r.Html
            Start-Process $r.Html
        })
    $u.DevFilter.Add_SelectionChanged({ Update-DeviceFilter })
    $u.DevSearch.Add_TextChanged({ Update-DeviceFilter })
    $u.DevGrid.Add_MouseDoubleClick({
            $sel = $script:Ui.DevGrid.SelectedItem
            if (-not $sel) { return }
            $d = $sel.Data
            $txt = "อุปกรณ์: {0}`nคลาส: {1}`nผู้ผลิตฮาร์ดแวร์: {2} ({3})`nผู้ให้ไดรเวอร์: {4}`nเวอร์ชัน/วันที่: {5} / {6}`nINF: {7}`nผู้ลงนาม: {8}`nการรับรอง: {9}`nสถานะ: {10}`nลำดับติดตั้ง: {11}`n`nHardware IDs:`n{12}`n`nDevice ID: {13}" -f $d.Name, $d.Class, $d.Manufacturer, $d.VendorName, $d.DriverProvider, $d.DriverVersion, $d.DriverDate, $d.InfName, $d.Signer, $d.CertText, $(if ($d.ProblemText) { $d.ProblemText } else { 'ปกติ' }), $d.OrderGroup, (($d.HardwareIds | Select-Object -First 6) -join "`n"), $d.DeviceId
            [void][Windows.MessageBox]::Show($txt, 'รายละเอียดไดรเวอร์')
        })
    $u.BtnUpdRecommended.Add_Click({
            foreach ($i in $script:Updates) {
                $i.Selected = switch ($i.Kind) { 'OemTool' { [bool]$i.Data.Automated -and $i.Level -ne 'ok' } 'VendorTool' { [bool]$i.Data.Default } 'WuDriver' { [bool]$i.Data.Selected } default { $false } }
            }
        })
    $u.BtnUpdAll.Add_Click({ foreach ($i in $script:Updates) { $i.Selected = $true } })
    $u.BtnUpdNone.Add_Click({ foreach ($i in $script:Updates) { $i.Selected = $false } })
    $u.BtnPresetRecommended.Add_Click({ Set-RuntimePreset 'recommended' })
    $u.BtnPresetGaming.Add_Click({ Set-RuntimePreset 'gaming' })
    $u.BtnPresetWork.Add_Click({ Set-RuntimePreset 'work' })
    $u.BtnPresetAll.Add_Click({ Set-RuntimePreset 'all' })
    $u.BtnPresetNone.Add_Click({ Set-RuntimePreset 'none' })
    $u.BtnAddFiles.Add_Click({
            $dlg = New-Object Microsoft.Win32.OpenFileDialog
            $dlg.Multiselect = $true
            $dlg.Title = 'เลือกไฟล์ไดรเวอร์/ตัวติดตั้ง'
            $dlg.Filter = 'ไฟล์ติดตั้งทั้งหมด|*.inf;*.exe;*.msi;*.msp;*.msu;*.cab;*.msix;*.msixbundle;*.appx;*.appxbundle;*.appinstaller;*.zip;*.7z;*.rar;*.tar;*.gz;*.tgz;*.iso;*.img;*.vhd;*.vhdx;*.bat;*.cmd;*.ps1;*.reg;*.ppkg|ทุกไฟล์|*.*'
            if ($dlg.ShowDialog()) { Add-UiPaths $dlg.FileNames }
        })
    $u.BtnAddFolder.Add_Click({
            $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
            $dlg.Description = 'เลือกโฟลเดอร์ที่มีไดรเวอร์ (.inf) หรือตัวติดตั้ง'
            if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { Add-UiPaths @($dlg.SelectedPath) }
        })
    $u.BtnRemoveFiles.Add_Click({ foreach ($s in @($script:Ui.FileGrid.SelectedItems)) { [void]$script:FilesCol.Remove($s) } })
    $u.FileGrid.Add_DragOver({
            param($sender, $e)
            $e.Effects = if ($e.Data.GetDataPresent([Windows.DataFormats]::FileDrop)) { [Windows.DragDropEffects]::Copy } else { [Windows.DragDropEffects]::None }
            $e.Handled = $true
        })
    $u.FileGrid.Add_Drop({
            param($sender, $e)
            if ($e.Data.GetDataPresent([Windows.DataFormats]::FileDrop)) { Add-UiPaths @($e.Data.GetData([Windows.DataFormats]::FileDrop)) }
        })
    $u.BtnOpenLogs.Add_Click({ Start-Process explorer.exe $script:Session.Root })
    $u.BtnOpenReport.Add_Click({
            $last = $script:LastReport
            if (-not $last) { $last = Get-ChildItem -LiteralPath $script:Session.ReportDir -Filter '*.html' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName }
            if ($last) { Start-Process $last } else { [void][Windows.MessageBox]::Show('ยังไม่มีรายงาน', 'Driver & Runtime Manager') }
        })
    $u.BtnInstall.Add_Click({ Invoke-UiInstallClick })
    $u.BtnStop.Add_Click({
            $script:Sync.Cancel = $true
            $script:Ui.TxtStatus.Text = 'กำลังหยุด — รอให้รายการที่กำลังติดตั้งจบก่อน (ไม่บังคับปิดกลางคันเพื่อความปลอดภัยของระบบ)'
            Add-UiLog '[STOP] ผู้ใช้สั่งหยุด — รายการที่เหลือจะถูกยกเลิก'
        })
    $u.Window.Add_Closing({
            param($sender, $e)
            if (Test-UiBusy) {
                $ans = [Windows.MessageBox]::Show('กำลังทำงานอยู่ การปิดตอนนี้อาจทำให้การติดตั้งไม่ครบ ต้องการปิดหรือไม่?', 'ยืนยันการปิด', 'YesNo', 'Warning')
                if ($ans -ne 'Yes') { $e.Cancel = $true; return }
                $script:Sync.Cancel = $true
            }
            $script:Timer.Stop()
        })

    $script:Tick = 0
    $script:Timer = New-Object System.Windows.Threading.DispatcherTimer
    $script:Timer.Interval = [TimeSpan]::FromMilliseconds(150)
    $script:InTick = $false
    $script:PendingRescan = $false
    $script:Timer.Add_Tick({
            if ($script:InTick) { return }
            $script:InTick = $true
            try {
            $sb = New-Object System.Text.StringBuilder
            $msg = $null; $n = 0
            while ($n -lt 400 -and $script:Queue.TryDequeue([ref]$msg)) {
                $n++
                try { Invoke-UiMessage $msg $sb } catch { [void]$sb.AppendLine('[UI] ' + $_.Exception.Message) }
            }
            if ($sb.Length -gt 0) { Add-UiLog ($sb.ToString().TrimEnd()) }
            Complete-UiWorkers
            $script:Tick++
            if ($script:Tick % 4 -eq 0) { Update-SelectionSummary }
            } finally { $script:InTick = $false }
        })
    $script:Timer.Start()

    $u.Window.Add_Loaded({
            Hide-ConsoleWindow
            $state = $null
            if ($Resume) { $state = Read-DrmResumeState -Root $script:Session.Root }
            if ($state) {
                Add-UiLog ("ทำงานต่อหลังรีสตาร์ทจากเซสชัน {0} อีก {1} รายการ" -f $state.SessionId, @($state.Items).Count)
                foreach ($p in @($state.Items)) {
                    $script:Updates.Add((New-GridItem @{ Id = $p.Id; Kind = 'Resume'; Source = 'งานต่อจากก่อนรีสตาร์ท'; Name = $p.Name; Comparison = $p.PhaseName; Status = 'รอทำต่อ' }))
                }
                $script:Ui.Tabs.SelectedIndex = 1
                Start-UiInstall -Plan @($state.Items) -Options $state.Options -Snapshot $state.Snapshot -ResumeAttempt ([int]$state.Attempt)
            }
            else { Start-UiScan -AutoCheck }
        })
    [void]$u.Window.ShowDialog()
    foreach ($w in @($script:Workers.Values)) { try { $w.PS.Stop(); $w.PS.Dispose(); $w.Runspace.Dispose() } catch { } }
}

# ---------------------------------------------------------------------------
# จุดเริ่มต้น
# ---------------------------------------------------------------------------
switch ($Mode) {
    'SelfTest' { exit (Invoke-SelfTest) }
    'Scan' { exit (Invoke-HeadlessScan) }
    'Install' { exit (Invoke-HeadlessInstall) }
    default {
        if (-not (Test-DrmIsWindows)) { Write-Host 'หน้าต่าง GUI ใช้ได้บน Windows เท่านั้น' -ForegroundColor Red; exit 2 }
        Start-Gui
    }
}
