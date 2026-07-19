param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string] $Command,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Arguments
)

$line = ((@($Command) + $Arguments) -join " ").Trim()
$pipe = [System.IO.Pipes.NamedPipeClientStream]::new(
    ".",
    "MoleculeControl",
    [System.IO.Pipes.PipeDirection]::InOut
)

try {
    $deadline = [DateTime]::UtcNow.AddSeconds(5)
    while (-not $pipe.IsConnected -and [DateTime]::UtcNow -lt $deadline) {
        try {
            $pipe.Connect(250)
        }
        catch [TimeoutException] {
        }
        catch [System.IO.IOException] {
        }
    }
    if (-not $pipe.IsConnected) {
        throw "Could not connect to the MoleculeControl pipe within five seconds."
    }
    $writer = [System.IO.StreamWriter]::new($pipe, [System.Text.UTF8Encoding]::new($false))
    $writer.AutoFlush = $true
    $writer.WriteLine($line)
    $reader = [System.IO.StreamReader]::new($pipe, [System.Text.UTF8Encoding]::new($false))
    $response = $reader.ReadLine()
    if ($null -eq $response) {
        throw "MoleculeControl closed without a response."
    }
    Write-Output $response
    if ($response.StartsWith("error ")) {
        exit 1
    }
}
finally {
    $pipe.Dispose()
}
