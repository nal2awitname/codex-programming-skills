@{
    # DRM-113: ใช้ใน CI (Invoke-ScriptAnalyzer -Path scripts -Recurse -Settings ./PSScriptAnalyzerSettings.psd1)
    # ระดับ Error และ Warning ต้องเป็นศูนย์ — กฎที่ยกเว้นด้านล่างเป็นการออกแบบที่ตั้งใจ
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # โหมดคำสั่งพิมพ์ผลเป็นสีให้ผู้ใช้อ่านบนคอนโซล ไม่ได้ส่งออกทาง pipeline
        'PSAvoidUsingWriteHost',
        # catch ว่างใช้กับการอ่านข้อมูลแบบ "ถ้าได้" (WMI/registry/ไฟล์ที่อาจไม่มี) — ข้อผิดพลาดจริงบันทึกด้วย Write-DrmLog
        'PSAvoidUsingEmptyCatchBlock',
        # ฟังก์ชันภายในของโมดูล ไม่ได้ออกแบบเป็น cmdlet สาธารณะที่ต้องมี -WhatIf (ใช้ -DryRun ของทั้งเซสชันแทน)
        'PSUseShouldProcessForStateChangingFunctions',
        # ชื่ออย่าง Get-DrmDriverPackages / Get-DrmDriverChanges สื่อว่าคืนหลายรายการ
        'PSUseSingularNouns',
        # คืนอาร์เรย์ทาง pipeline โดยไม่ประกาศ [OutputType()]
        'PSUseOutputTypeCorrectly'
    )
}
