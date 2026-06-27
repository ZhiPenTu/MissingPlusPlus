//! Tauri IPC bridge — invoke wrapper + listen event subscription

import { invoke } from '@tauri-apps/api/core'
import { listen, UnlistenFn } from '@tauri-apps/api/event'

export async function call<T>(cmd: string, args?: Record<string, unknown>): Promise<T> {
  return invoke<T>(cmd, args)
}

export async function onStoreChanged(handler: () => void): Promise<UnlistenFn> {
  return listen('store:changed', () => handler())
}
