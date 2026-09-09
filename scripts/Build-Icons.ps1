#Requires -Version 5.1
<#
.SYNOPSIS
  Turn the designed app PNG into a true-alpha PNG plus a multi-size ICO.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourcePng,
    [Parameter(Mandatory = $true)][string]$OutPng,
    [Parameter(Mandatory = $true)][string]$OutIco
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

$iconCs = @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;

public static class GrokIconBuild {
    public static Bitmap Clean(Bitmap src) {
        int w = src.Width, h = src.Height;
        Bitmap dst = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        BitmapData sdata = src.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        BitmapData ddata = dst.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        int sStride = sdata.Stride, dStride = ddata.Stride;
        byte[] sbytes = new byte[sStride * h];
        byte[] dbytes = new byte[dStride * h];
        Marshal.Copy(sdata.Scan0, sbytes, 0, sbytes.Length);
        src.UnlockBits(sdata);

        // src may have been 24bpp copied into a 32bpp lock — treat RGB, force opaque
        for (int y = 0; y < h; y++) {
            int so = y * sStride, dOff = y * dStride;
            for (int x = 0; x < w; x++) {
                dbytes[dOff + x * 4 + 0] = sbytes[so + x * 4 + 0];
                dbytes[dOff + x * 4 + 1] = sbytes[so + x * 4 + 1];
                dbytes[dOff + x * 4 + 2] = sbytes[so + x * 4 + 2];
                dbytes[dOff + x * 4 + 3] = 255;
            }
        }

        bool[] seen = new bool[w * h];
        int[] q = new int[w * h];
        int qs = 0, qe = 0;
        Action<int,int> enq = delegate(int x, int y) {
            if (x < 0 || y < 0 || x >= w || y >= h) return;
            int i = y * w + x;
            if (seen[i]) return;
            seen[i] = true;
            q[qe++] = i;
        };
        for (int x = 0; x < w; x++) { enq(x, 0); enq(x, h - 1); }
        for (int y = 0; y < h; y++) { enq(0, y); enq(w - 1, y); }

        while (qs < qe) {
            int i = q[qs++];
            int x = i % w, y = i / w;
            int o = y * dStride + x * 4;
            byte b = dbytes[o], g = dbytes[o + 1], r = dbytes[o + 2];
            bool plate = r < 70 && g < 70 && b < 70;
            bool blue = b > 160 && b > r + 30 && b > g + 30;
            if (plate || blue) continue;
            dbytes[o] = 0; dbytes[o + 1] = 0; dbytes[o + 2] = 0; dbytes[o + 3] = 0;
            enq(x + 1, y); enq(x - 1, y); enq(x, y + 1); enq(x, y - 1);
        }

        Marshal.Copy(dbytes, 0, ddata.Scan0, dbytes.Length);
        dst.UnlockBits(ddata);
        return dst;
    }

    public static Bitmap OpaqueSquare(Bitmap src, int size) {
        Bitmap b = new Bitmap(size, size, PixelFormat.Format32bppArgb);
        using (Graphics g = Graphics.FromImage(b)) {
            g.Clear(Color.Black);
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.SmoothingMode = SmoothingMode.HighQuality;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            g.CompositingQuality = CompositingQuality.HighQuality;
            g.DrawImage(src, 0, 0, size, size);
        }
        BitmapData data = b.LockBits(new Rectangle(0, 0, size, size), ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
        int bytes = Math.Abs(data.Stride) * size;
        byte[] buf = new byte[bytes];
        Marshal.Copy(data.Scan0, buf, 0, bytes);
        for (int i = 0; i < buf.Length; i += 4) {
            if (buf[i + 3] < 250) {
                buf[i] = 0; buf[i + 1] = 0; buf[i + 2] = 0; buf[i + 3] = 255;
            }
        }
        Marshal.Copy(buf, 0, data.Scan0, bytes);
        b.UnlockBits(data);
        return b;
    }

    public static void WriteIco(string path, Bitmap[] frames, int[] sizes) {
        var pngs = new List<byte[]>();
        for (int i = 0; i < frames.Length; i++) {
            using (var ms = new MemoryStream()) {
                frames[i].Save(ms, ImageFormat.Png);
                pngs.Add(ms.ToArray());
            }
        }
        using (var fs = new FileStream(path, FileMode.Create, FileAccess.Write))
        using (var bw = new BinaryWriter(fs)) {
            bw.Write((short)0);
            bw.Write((short)1);
            bw.Write((short)pngs.Count);
            int offset = 6 + 16 * pngs.Count;
            for (int i = 0; i < pngs.Count; i++) {
                int sz = sizes[i];
                bw.Write((byte)(sz < 256 ? sz : 0));
                bw.Write((byte)(sz < 256 ? sz : 0));
                bw.Write((byte)0);
                bw.Write((byte)0);
                bw.Write((short)1);
                bw.Write((short)32);
                bw.Write(pngs[i].Length);
                bw.Write(offset);
                offset += pngs[i].Length;
            }
            foreach (var p in pngs) bw.Write(p);
        }
    }
}
'@

Add-Type -TypeDefinition $iconCs -ReferencedAssemblies System.Drawing -ErrorAction Stop

$raw = [System.Drawing.Bitmap]::FromFile($SourcePng)
try {
    $src32 = New-Object System.Drawing.Bitmap $raw.Width, $raw.Height, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($src32)
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.DrawImage($raw, 0, 0, $raw.Width, $raw.Height)
    $g.Dispose()
} finally {
    $raw.Dispose()
}

$clean = [GrokIconBuild]::Clean($src32)
$src32.Dispose()

$outDir = Split-Path -Parent $OutPng
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
$clean.Save($OutPng, [System.Drawing.Imaging.ImageFormat]::Png)

$sizes = @(16, 20, 24, 32, 40, 48, 64, 128, 256)
$frames = New-Object 'System.Drawing.Bitmap[]' $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $frames[$i] = [GrokIconBuild]::OpaqueSquare($clean, $sizes[$i])
}
[GrokIconBuild]::WriteIco($OutIco, $frames, $sizes)
foreach ($f in $frames) { $f.Dispose() }
$clean.Dispose()

Write-Output "PNG $OutPng ($((Get-Item $OutPng).Length) bytes)"
Write-Output "ICO $OutIco ($((Get-Item $OutIco).Length) bytes)"
