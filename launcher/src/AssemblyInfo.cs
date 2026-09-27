// SPDX-License-Identifier: AGPL-3.0-or-later
using System.Reflection;
using System.Runtime.Versioning;

// Without this attribute .NET Framework runs the app in 4.0 compatibility mode,
// which leaves TLS 1.2 off by default and breaks the HTTPS news requests.
[assembly: TargetFramework(".NETFramework,Version=v4.8", FrameworkDisplayName = ".NET Framework 4.8")]
[assembly: AssemblyTitle("Crown & Card Launcher")]
[assembly: AssemblyProduct("Crown & Card")]
[assembly: AssemblyCopyright("Copyright (C) 2026 David Kendig. AGPL-3.0-or-later.")]
// Version attributes come from version.json via bin/generated/BuildInfo.cs (see build.ps1).
