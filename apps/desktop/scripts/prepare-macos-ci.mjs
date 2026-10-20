/** Validate machine-owned macOS signing settings and record a manual Actions build version. */
import { appendFileSync, readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { execFileSync } from 'node:child_process'
import { desktopTargetPlatform, resolveDesktopBuildTarget } from './desktop-build-paths.mjs'
import { desktopCiVersion } from './desktop-ci-version.mjs'
import { loadDesktopPackageEnvironment, validateDesktopPackageEnvironment } from './desktop-package-environment.mjs'

/** Packaging entry each macOS target runs; the x64 entry also marks sources that support target selection. */
const PACKAGE_SCRIPTS = {
  'mac-arm64': 'package:desktop:mac:arm64',
  'mac-x64': 'package:desktop:mac:x64',
}

const appRoot = resolve(import.meta.dirname, '..')
const product = JSON.parse(readFileSync(resolve(appRoot, 'package.json'), 'utf8'))
const version = desktopCiVersion(process.env, product.version)
if (!process.env.DSH_PACKAGING_PRESET) throw new Error('Select a machine preset')
const skipNotarization = process.env.PACKAGE_SKIP_NOTARIZATION === 'true'
if (!['true', 'false', undefined].includes(process.env.PACKAGE_SKIP_NOTARIZATION)) throw new Error('Invalid skip notarization selection')
if (process.env.DSH_DESKTOP_TARGET_PLATFORM !== 'darwin') throw new Error('Select a macOS build target')
if (process.env.DSH_DESKTOP_TARGET_ARCH !== 'arm64' && process.env.DSH_DESKTOP_TARGET_ARCH !== 'x64') {
  throw new Error('Select a macOS build target architecture')
}
const target = resolveDesktopBuildTarget(process.env)
const { platform, arch } = desktopTargetPlatform(target)
const environment = loadDesktopPackageEnvironment(platform, process.env, appRoot)
for (const [name, value] of Object.entries(environment)) {
  if (/KEY|TOKEN|PASSWORD|SECRET|APPLE_ID/iu.test(name) && value) {
    const escaped = value.replaceAll('%', '%25').replaceAll('\r', '%0D').replaceAll('\n', '%0A')
    process.stdout.write(`::add-mask::${escaped}\n`)
  }
}
validateDesktopPackageEnvironment(environment, { platform, arch }, { skipNotarization })
if (!process.env.GITHUB_OUTPUT || !process.env.GITHUB_STEP_SUMMARY) throw new Error('Run this adapter from GitHub Actions')
appendFileSync(process.env.GITHUB_OUTPUT, `version=${version}\narch=${arch}\ntarget=${target}\nartifacts=${skipNotarization ? 'unnotarized-artifacts' : 'artifacts'}\nmode=${skipNotarization ? 'unnotarized-debug' : 'signed'}\npackage_script=${PACKAGE_SCRIPTS[target]}\n`)
appendFileSync(process.env.GITHUB_STEP_SUMMARY, `macOS ${arch} signed installer\n\nVersion: ${version}\n\nTarget: ${target}\n\nCommit: ${execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).trim()}\n\nChannel: ${process.env.DSH_DESKTOP_UPDATE_CHANNEL}\n\nSource: ${process.env.PACKAGE_SOURCE_REF}\n\nPreset: ${process.env.DSH_PACKAGING_PRESET}\n`)
if (skipNotarization) appendFileSync(process.env.GITHUB_STEP_SUMMARY, '\nWARNING: signed but NOT notarized or stapled. Internal debugging only; Gatekeeper may block downloaded copies. Not qualified for distribution or update publishing.\n')
