export interface RuntimePatchResult {
  success: boolean
  bytes: number
  message: string
}

export const writeRuntimePatchFile: (targetPath: string) => RuntimePatchResult
export const writeExplorerPatchFile: (targetPath: string) => RuntimePatchResult
export const writeNtdllPatchFile: (targetPath: string) => RuntimePatchResult
export const writeWin32uPatchFile: (targetPath: string) => RuntimePatchResult
