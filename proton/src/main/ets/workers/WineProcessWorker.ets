import hilog from '@ohos.hilog'
import worker from '@ohos.worker'
import protonNative from 'libproton.so'

const LOG_DOMAIN: number = 0x2330
const LOG_TAG: string = 'WineProcessWorker'

interface NativeLaunchSession {
  sessionId: string
  status: string
  reason: string
  exitCode?: number
}

interface NativeProtonModule {
  launchSessionInCurrentProcess(launchRequest: string): NativeLaunchSession
}

interface WineWorkerLaunchMessage {
  type: string
  requestId: string
  slotId: number
  launchRequest: string
}

interface WineWorkerResultMessage {
  type: string
  requestId: string
  slotId: number
  status: string
  reason: string
  exitCode?: number
}

const nativeBridge = protonNative as NativeProtonModule

function postResult(message: WineWorkerResultMessage): void {
  worker.workerPort.postMessage(message)
}

function errorMessage(err: Error | Object): string {
  if (err instanceof Error) {
    return err.message
  }
  return `${err}`
}

worker.workerPort.onmessage = (event): void => {
  const message = event.data as WineWorkerLaunchMessage
  if (message.type !== 'launch' || message.launchRequest.length === 0) {
    postResult({
      type: 'failed',
      requestId: message.requestId ? message.requestId : '',
      slotId: message.slotId ? message.slotId : -1,
      status: 'invalid-command',
      reason: 'invalid Wine worker launch message'
    })
    worker.workerPort.close()
    return
  }

  postResult({
    type: 'started',
    requestId: message.requestId,
    slotId: message.slotId,
    status: 'started',
    reason: `worker emulated Wine process slot=${message.slotId}`
  })

  try {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'worker slot=%{public}d entering native runtime', message.slotId)
    const result = nativeBridge.launchSessionInCurrentProcess(message.launchRequest)
    postResult({
      type: result.status === 'runtime-error' ? 'failed' : 'finished',
      requestId: message.requestId,
      slotId: message.slotId,
      status: result.status,
      reason: result.reason,
      exitCode: result.exitCode
    })
  } catch (err) {
    postResult({
      type: 'failed',
      requestId: message.requestId,
      slotId: message.slotId,
      status: 'runtime-error',
      reason: errorMessage(err)
    })
  }
  worker.workerPort.close()
}
