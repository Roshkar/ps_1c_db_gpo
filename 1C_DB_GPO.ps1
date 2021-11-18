<# VARIABLES #>

<# Путь к файлу csv, содержащему данные о пользователях#>
$CsvPath="\\contoso.com\scripts\1C\1C_DB_GPO.csv"

<# Разделитель значений файла csv #>
$CsvDelimiter=";"

<# Заголовки csv #>
$GroupHeader = 'Группа пользователей'
$ConfigFileHeader = 'Файл конфигурации БД'

<# END VARIABLES #>

<# Ведение файла журнала #>
function Write-Log {
    Param(
        $Message,
        $Path = "C:\1c_db_gpo_log.txt"
    )

    function TS {Get-Date -Format 'hh:mm:ss'}
    Write-Output "[$(TS)]$Message" | Out-File $Path -Append
}

Write-Log $CsvPath

<# Текущий пользователь #>
$User = $env:username

Write-Log $User

<# Получение содержимого csv-файла #>
$BaseCsv = Get-Content $CsvPath | ConvertFrom-Csv -delimiter $CsvDelimiter

Write-Log $BaseCsv

<# Получение групп пользователей #>
$GroupsArray = $BaseCsv | Select -Expand $GroupHeader

Write-Log $GroupsArray

<# Результирующий массив баз данных пользователя #>
$ResultDbArray = @()

foreach ($Group in $GroupsArray) {
    $ADGroupObj = (([ADSISearcher] "(&(objectCategory=person)(objectClass=user)(sAMAccountName=$user))").FindOne().properties.memberof -match "CN=$Group,")
    if ($ADGroupObj -and $ADGroupObj.count -gt 0)
    {
       $ResultDbArray += $BaseCsv | Where-Object {$_.$GroupHeader -eq $Group}
    }
}

Write-Log $ResultDbArray

<# Получение путей к файлам конфигурации БД 1С #>
$BasesConfig = $ResultDbArray | Select -Expand $ConfigFileHeader

Write-Log $BasesConfig

<# Генерация строки подключения файлов конфигурации БД 1С #>
$Result = @()
foreach ($config in $BasesConfig) {
    $Result += "CommonInfoBases="+$config
}

Write-Log $Result

<# Сохранение в каталог пользователя %APPDATA% #>
$ResultPath = $env:APPDATA + "\1C\1CEStart\1CEStart.cfg"
$Result | Out-File -FilePath $ResultPath