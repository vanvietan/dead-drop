# Generates the Viewpoint (first-person) model pack for the LootBox Gatcha Machine.
#
# Writes into Contents/mods/LootBox/common/media/viewpoint/:
#   lootbox.properties      Viewpoint model-pack manifest (model + sprite binds)
#   gatcha/gatcha.obj       low-poly box model, Z up, tile units, origin at tile centre, floor at z=0
#   gatcha/gatcha.mtl       material pointing at the atlas
#   gatcha/gatcha.png       64x64 colour/art atlas
#
# Run from anywhere:  powershell -ExecutionPolicy Bypass -File tools/viewpoint/gen_gatcha_model.ps1

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$inv = [Globalization.CultureInfo]::InvariantCulture
$utf8 = New-Object Text.UTF8Encoding($false)
$outDir = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\Contents\mods\LootBox\common\media\viewpoint'))
$modelDir = Join-Path $outDir 'gatcha'
New-Item -ItemType Directory -Force $modelDir | Out-Null

$MODEL_ID = 'lootbox-gatcha'

# Sprite -> rotation (degrees about Z) applied to the model, whose front faces -Y.
# Facings are read from the isometric art (front on the left face = +Y/south, right face = +X/east).
$BINDS = [ordered]@{
    'dead_drop_gatcha_01_0' = 180  # front +Y (S)
    'dead_drop_gatcha_01_1' = 0    # front -Y (N)
    'dead_drop_gatcha_01_2' = -90  # front -X (W)
    'dead_drop_gatcha_01_3' = 90   # front +X (E)
}

# ---------------------------------------------------------------- atlas
$ATLAS = 64
# Flat colour cells: name -> (x, y, w, h, colour). Art cells are painted separately below.
$cells = [ordered]@{
    cream = @(0, 0, 8, 8, '#E8E0CF')
    side  = @(8, 0, 8, 8, '#9EA3A8')
    lid   = @(16, 0, 8, 8, '#D6D7DA')
    cap   = @(24, 0, 8, 8, '#EDEEF0')
    base  = @(0, 8, 8, 8, '#6B6F74')
    dark  = @(8, 8, 8, 8, '#25272A')
    red   = @(16, 8, 8, 8, '#D23A32')
    blue  = @(24, 8, 8, 8, '#2F62C9')
    frame = @(0, 16, 8, 8, '#B9BDC1')
    flap  = @(8, 16, 8, 8, '#4A4D50')
    vent  = @(16, 16, 8, 8, '#7A7E83')
    panel = @(0, 32, 32, 32, $null)   # coin panel art
    glass = @(32, 32, 32, 32, $null)  # capsule window art
}

$bmp = New-Object Drawing.Bitmap $ATLAS, $ATLAS
$g = [Drawing.Graphics]::FromImage($bmp)
$g.Clear([Drawing.Color]::Transparent)
foreach ($name in $cells.Keys) {
    $c = $cells[$name]
    if ($c[4]) {
        $brush = New-Object Drawing.SolidBrush ([Drawing.ColorTranslator]::FromHtml($c[4]))
        $g.FillRectangle($brush, $c[0], $c[1], $c[2], $c[3])
        $brush.Dispose()
    }
}
function Brush($hex) { New-Object Drawing.SolidBrush ([Drawing.ColorTranslator]::FromHtml($hex)) }

# Coin panel: dark plate, green display, coin slot, change cup.
$g.FillRectangle((Brush '#3A3D41'), 0, 32, 32, 32)
$g.FillRectangle((Brush '#2BB673'), 3, 36, 14, 6)
$g.FillRectangle((Brush '#C9CDD1'), 21, 36, 7, 10)
$g.FillRectangle((Brush '#111214'), 23, 38, 3, 6)
$g.FillRectangle((Brush '#1B1C1E'), 4, 50, 12, 9)

# Capsule window: pale glass with stacked coloured capsules and a glare streak.
$g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.FillRectangle((Brush '#CFE3EA'), 32, 32, 32, 32)
$balls = @('#E2463F', '#3C7DE0', '#4DB85A', '#F2C230', '#E07AC0', '#F08A2E')
$rng = New-Object Random 42
for ($row = 0; $row -lt 4; $row++) {
    for ($col = 0; $col -lt 4; $col++) {
        $bx = 32 + 1 + $col * 8 - ($row % 2) * 3 + $rng.Next(0, 2)
        $by = 32 + 30 - ($row + 1) * 7 + $rng.Next(0, 2)
        $g.FillEllipse((Brush $balls[$rng.Next(0, $balls.Count)]), $bx, $by, 8, 8)
        $g.FillEllipse((Brush '#F4F4F4'), $bx + 4, $by + 4, 4, 4)
    }
}
$g.FillRectangle((New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(90, 255, 255, 255))), 52, 33, 3, 30)
$g.Dispose()
$bmp.Save((Join-Path $modelDir 'gatcha.png'), [Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

# UV rect for a cell; flat cells are inset so filtering never bleeds into neighbours.
function CellUv($name) {
    $c = $cells[$name]
    $inset = if ($c[4]) { 2 } else { 0.5 }
    $u0 = ($c[0] + $inset) / $ATLAS; $u1 = ($c[0] + $c[2] - $inset) / $ATLAS
    $v0 = 1 - ($c[1] + $c[3] - $inset) / $ATLAS; $v1 = 1 - ($c[1] + $inset) / $ATLAS
    return @($u0, $v0, $u1, $v1)
}

# ---------------------------------------------------------------- geometry
$verts = New-Object Collections.Generic.List[string]
$uvs = New-Object Collections.Generic.List[string]
$faces = New-Object Collections.Generic.List[string]
$normals = @('0 -1 0', '0 1 0', '-1 0 0', '1 0 0', '0 0 1', '0 0 -1')
$faceIndex = @{ '-y' = 1; '+y' = 2; '-x' = 3; '+x' = 4; '+z' = 5; '-z' = 6 }
$bounds = @([double]::MaxValue, [double]::MinValue, [double]::MaxValue, [double]::MinValue, [double]::MaxValue, [double]::MinValue)

function Quad($corners, $uv, $normal) {
    $base = $verts.Count
    foreach ($p in $corners) {
        $verts.Add([string]::Format($inv, 'v {0:0.0000} {1:0.0000} {2:0.0000}', $p[0], $p[1], $p[2]))
        for ($i = 0; $i -lt 3; $i++) {
            if ($p[$i] -lt $bounds[$i * 2]) { $bounds[$i * 2] = $p[$i] }
            if ($p[$i] -gt $bounds[$i * 2 + 1]) { $bounds[$i * 2 + 1] = $p[$i] }
        }
    }
    $uvBase = $uvs.Count
    foreach ($t in @(@($uv[0], $uv[1]), @($uv[2], $uv[1]), @($uv[2], $uv[3]), @($uv[0], $uv[3]))) {
        $uvs.Add([string]::Format($inv, 'vt {0:0.000000} {1:0.000000}', $t[0], $t[1]))
    }
    $i = @(1..4 | ForEach-Object { "$($base + $_)/$($uvBase + $_)/$normal" })
    $faces.Add("f $($i[0]) $($i[1]) $($i[2])")
    $faces.Add("f $($i[0]) $($i[2]) $($i[3])")
}

# Axis-aligned box. $skin maps face keys (-y,+y,-x,+x,+z,-z) or 'all' to a cell name; missing faces are skipped.
function Box($x0, $x1, $y0, $y1, $z0, $z1, $skin) {
    $get = { param($k) if ($skin.ContainsKey($k)) { $skin[$k] } elseif ($skin.ContainsKey('all')) { $skin['all'] } else { $null } }
    $quads = @{
        '-y' = @(@($x0, $y0, $z0), @($x1, $y0, $z0), @($x1, $y0, $z1), @($x0, $y0, $z1))
        '+y' = @(@($x1, $y1, $z0), @($x0, $y1, $z0), @($x0, $y1, $z1), @($x1, $y1, $z1))
        '-x' = @(@($x0, $y1, $z0), @($x0, $y0, $z0), @($x0, $y0, $z1), @($x0, $y1, $z1))
        '+x' = @(@($x1, $y0, $z0), @($x1, $y1, $z0), @($x1, $y1, $z1), @($x1, $y0, $z1))
        '+z' = @(@($x0, $y0, $z1), @($x1, $y0, $z1), @($x1, $y1, $z1), @($x0, $y1, $z1))
        '-z' = @(@($x0, $y1, $z0), @($x1, $y1, $z0), @($x1, $y0, $z0), @($x0, $y0, $z0))
    }
    foreach ($k in @('-y', '+y', '-x', '+x', '+z', '-z')) {
        $cell = & $get $k
        if ($cell) { Quad $quads[$k] (CellUv $cell) $faceIndex[$k] }
    }
}

# Sizes follow the isometric sprite: ~0.62 tile footprint, ~1.72 tiles tall (a wall is ~2.46).
$h = 0.30
Box (-0.32) 0.32 (-0.32) 0.32 0.00 0.08 @{ all = 'base'; '-z' = $null }                        # plinth
Box (-$h) $h (-$h) $h 0.08 1.60 @{ '-y' = 'cream'; '+y' = 'cream'; '-x' = 'side'; '+x' = 'side' }  # cabinet
Box (-0.31) 0.31 (-0.31) 0.31 1.60 1.68 @{ all = 'lid'; '-z' = 'lid' }                          # lid
Box (-0.26) 0.26 (-0.26) 0.26 1.68 1.71 @{ all = 'cap'; '-z' = $null }                          # lid cap
Box (-0.24) 0.24 (-0.312) (-$h) 0.92 1.52 @{ all = 'frame'; '+y' = $null }                      # window frame
Box (-0.21) 0.21 (-0.322) (-0.312) 0.95 1.49 @{ '-y' = 'glass'; '-x' = 'frame'; '+x' = 'frame'; '+z' = 'frame'; '-z' = 'frame' } # glass
Box (-0.22) 0.06 (-0.315) (-$h) 0.58 0.84 @{ '-y' = 'panel'; '-x' = 'dark'; '+x' = 'dark'; '+z' = 'dark'; '-z' = 'dark' }      # coin panel
Box 0.09 0.15 (-0.335) (-$h) 0.66 0.72 @{ all = 'red'; '+y' = $null }                          # red button
Box 0.17 0.23 (-0.335) (-$h) 0.66 0.72 @{ all = 'blue'; '+y' = $null }                         # blue button
Box (-0.18) 0.18 (-0.306) (-$h) 0.18 0.44 @{ all = 'dark'; '+y' = $null }                      # prize chute
Box (-0.16) 0.16 (-0.312) (-0.306) 0.34 0.42 @{ all = 'flap'; '+y' = $null }                   # chute flap
foreach ($z in @(1.30, 1.36, 1.42, 0.26, 0.32)) {                                               # back vents
    Box (-0.15) 0.15 $h 0.304 $z ($z + 0.025) @{ all = 'vent'; '-y' = $null }
}

# ---------------------------------------------------------------- write
$obj = New-Object Text.StringBuilder
[void]$obj.AppendLine('# LootBox Gatcha Machine for Viewpoint - generated by tools/viewpoint/gen_gatcha_model.ps1')
[void]$obj.AppendLine('# Z up, tile units, origin at tile centre, front faces -Y')
[void]$obj.AppendLine('mtllib gatcha.mtl')
[void]$obj.AppendLine('usemtl atlas')
foreach ($l in $verts) { [void]$obj.AppendLine($l) }
foreach ($l in $uvs) { [void]$obj.AppendLine($l) }
foreach ($n in $normals) { [void]$obj.AppendLine("vn $n") }
foreach ($l in $faces) { [void]$obj.AppendLine($l) }
[IO.File]::WriteAllText((Join-Path $modelDir 'gatcha.obj'), $obj.ToString().Replace("`r`n", "`n"), $utf8)

[IO.File]::WriteAllText((Join-Path $modelDir 'gatcha.mtl'), "newmtl atlas`nKd 1 1 1`nd 1`nmap_Kd gatcha.png`n", $utf8)

# Viewpoint's manifest parser rejects lines without key=value, so the manifest carries no comments.
# Bind format: bind.<sprite>=<model>,<degrees>,<x>,<y>,<z>,<scale>
$manifest = New-Object Text.StringBuilder
[void]$manifest.AppendLine('id=lootbox-gatcha')
[void]$manifest.AppendLine('name=LootBox Gatcha Machine')
[void]$manifest.AppendLine('version=1')
[void]$manifest.AppendLine("model.$MODEL_ID=gatcha/gatcha.obj")
foreach ($sprite in $BINDS.Keys) { [void]$manifest.AppendLine("bind.$sprite=$MODEL_ID,$($BINDS[$sprite]),0,0,0,1") }
[IO.File]::WriteAllText((Join-Path $outDir 'lootbox.properties'), $manifest.ToString().Replace("`r`n", "`n"), $utf8)

Write-Host ([string]::Format($inv, 'Wrote {0}: {1} vertices, {2} triangles', $outDir, $verts.Count, $faces.Count))
Write-Host ([string]::Format($inv, 'Bounds x[{0:0.###}, {1:0.###}] y[{2:0.###}, {3:0.###}] z[{4:0.###}, {5:0.###}]', $bounds[0], $bounds[1], $bounds[2], $bounds[3], $bounds[4], $bounds[5]))
