//! React Query hooks — server state (records) wired to Rust commands

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { useEffect } from 'react'
import { call, onStoreChanged } from './tauri'
import type { Missing, Mood, Intensity, TriggerTag, RealityCheck } from '../domain/model'

const RECORDS_KEY = ['records'] as const

export function useRecords() {
  const qc = useQueryClient()
  useEffect(() => {
    let unlisten: (() => void) | null = null
    onStoreChanged(() => qc.invalidateQueries({ queryKey: RECORDS_KEY }))
      .then(u => { unlisten = u })
    return () => { if (unlisten) unlisten() }
  }, [qc])
  return useQuery({
    queryKey: RECORDS_KEY,
    queryFn: () => call<Missing[]>('load_records'),
  })
}

export function useAddMissing() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (input: {
      who: string; mood: Mood; intensity: Intensity; trigger_tags: TriggerTag[]
    }) => call<Missing>('add_missing', input),
    onSuccess: () => qc.invalidateQueries({ queryKey: RECORDS_KEY }),
  })
}

export function useMarkResolved() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (id: string) => call<void>('mark_resolved', { id }),
    onSuccess: () => qc.invalidateQueries({ queryKey: RECORDS_KEY }),
  })
}

export function useAttachRealityCheck() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ id, check }: { id: string; check: RealityCheck }) =>
      call<void>('attach_reality_check', { id, check }),
    onSuccess: () => qc.invalidateQueries({ queryKey: RECORDS_KEY }),
  })
}

export function useUpdateTriggers() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ id, tags }: { id: string; tags: TriggerTag[] }) =>
      call<void>('update_triggers', { id, tags }),
    onSuccess: () => qc.invalidateQueries({ queryKey: RECORDS_KEY }),
  })
}

export function useDeleteMissing() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (id: string) => call<void>('delete_missing', { id }),
    onSuccess: () => qc.invalidateQueries({ queryKey: RECORDS_KEY }),
  })
}

export function useClearAllRecords() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: () => call<void>('clear_all_records'),
    onSuccess: () => qc.invalidateQueries({ queryKey: RECORDS_KEY }),
  })
}
