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
    [System.IO.Pipes.PipeDirection]::Out
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
    $writer.WriteLine($line)
    $writer.Flush()
}
finally {
    $pipe.Dispose()
}
