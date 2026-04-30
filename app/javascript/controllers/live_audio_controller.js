import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"
export default class extends Controller {
  static targets = ["toggle", "current", "duration", "progress", "icon", "waveform"]
  static values = { conversationId: Number, token: String }

  connect() {
    this.audioContext = null
    this.isEnabled = false
    this.subscription = null
    this.rings = null
    this.playbackNode = null
    this.started = false
    this.analyser = null
    this.waveformAnimation = null
    this.resizeWaveformBound = () => this.resizeWaveform()
  }

  disconnect() {
    this.stopAudio()
  }

  toggle() {
    if (this.isEnabled) {
      this.stopAudio()
      return
    }

    this.isEnabled = true
    this.setToggleIcon("pause")
    this.updateLabels({ current: "Listening...", duration: "Live" })
    this.ensureAudioContext()
    if (this.audioContext?.state === "suspended") {
      this.audioContext.resume()
    }
    this.connectActionCable()
  }

  connectActionCable() {
    if (this.subscription) return
    if (!this.isEnabled) return
    if (!this.hasConversationIdValue) return
    if (!this.hasTokenValue || !this.tokenValue) return

    this.subscription = consumer.subscriptions.create(
      {
        channel: "CallAudioChannel",
        conversation_id: this.conversationIdValue,
        token: this.tokenValue
      },
      {
        received: (data) => this.handleAudio(data)
      }
    )
  }

  disconnectActionCable() {
    if (!this.subscription) return
    this.subscription.unsubscribe()
    this.subscription = null
  }

  handleAudio(data) {
    if (!this.isEnabled || !data) return
    const media = this.extractMedia(data)
    if (!media) return

    this.ensureAudioContext()
    if (!this.audioContext) return

    const decoded = this.decodeMuLaw(media.payload)
    if (!decoded.length) return

    const samples = this.resampleToContext(decoded, 8000, this.audioContext.sampleRate)
    if (!samples.length) return

    this.writeToRing(samples, media.track)
  }

  ensureAudioContext() {
    if (this.audioContext) return
    const AudioContextClass = window.AudioContext || window.webkitAudioContext
    this.audioContext = new AudioContextClass({ sampleRate: 8000 })
    this.initRingBuffer()
    this.initPlaybackNode()
    this.connectPlayback()
  }

  stopAudio() {
    this.isEnabled = false
    this.disconnectActionCable()
    if (this.audioContext) {
      if (this.playbackNode) {
        this.playbackNode.disconnect()
      }
      if (this.analyser) {
        this.analyser.disconnect()
      }
      this.audioContext.close()
      this.audioContext = null
    }
    this.playbackNode = null
    this.analyser = null
    this.rings = null
    this.started = false
    this.stopWaveform()
    this.setToggleIcon("play")
    this.updateLabels({ current: "Stopped", duration: "Live" })
  }

  updateLabels({ current, duration }) {
    if (this.hasCurrentTarget) this.currentTarget.textContent = current
    if (this.hasDurationTarget) this.durationTarget.textContent = duration
    if (this.hasProgressTarget) this.progressTarget.value = 0
  }

  setToggleIcon(state) {
    if (!this.hasIconTarget) return
    if (state === "pause") {
      this.iconTarget.innerHTML = "<rect x='6' y='4' width='4' height='16'></rect><rect x='14' y='4' width='4' height='16'></rect>"
    } else {
      this.iconTarget.innerHTML = "<polygon points='6 4 20 12 6 20 6 4'></polygon>"
    }
  }

  extractMedia(data) {
    if (data.type === "media" && data.payload) {
      return { payload: data.payload, track: data.track || "inbound" }
    }
    if (data.event === "media" && data.media?.payload) {
      return { payload: data.media.payload, track: data.media.track || "inbound" }
    }
    return null
  }

  initRingBuffer() {
    const ringSeconds = 1
    const rate = this.audioContext.sampleRate
    const ringSize = Math.max(1, Math.floor(rate * ringSeconds))
    const createRing = () => ({
      buffer: new Float32Array(ringSize),
      size: ringSize,
      read: 0,
      write: 0,
      available: 0
    })
    this.rings = {
      inbound: createRing(),
      outbound: createRing()
    }
    this.started = false
  }

  initPlaybackNode() {
    if (!this.audioContext || this.playbackNode) return

    const bufferSize = 1024
    const node = this.audioContext.createScriptProcessor(bufferSize, 0, 1)
    node.onaudioprocess = (event) => {
      const output = event.outputBuffer.getChannelData(0)
      const startThreshold = Math.floor(this.audioContext.sampleRate * 0.15)
      const underrunThreshold = Math.floor(this.audioContext.sampleRate * 0.08)

      if (!this.started && this.maxAvailable() < startThreshold) {
        output.fill(0)
        return
      }

      this.started = true
      if (this.maxAvailable() < underrunThreshold) {
        this.started = false
        output.fill(0)
        return
      }

      this.readFromRing(output)
    }
    this.playbackNode = node
  }

  connectPlayback() {
    if (!this.audioContext || !this.playbackNode) return
    if (this.hasWaveformTarget) {
      this.analyser = this.audioContext.createAnalyser()
      this.analyser.fftSize = 256
      this.playbackNode.connect(this.analyser)
      this.analyser.connect(this.audioContext.destination)
      this.initWaveform()
    } else {
      this.playbackNode.connect(this.audioContext.destination)
    }
  }

  initWaveform() {
    if (!this.hasWaveformTarget) return
    this.resizeWaveform()
    this.startWaveform()
    window.addEventListener("resize", this.resizeWaveformBound)
  }

  resizeWaveform() {
    if (!this.hasWaveformTarget) return
    const ratio = window.devicePixelRatio || 1
    const canvas = this.waveformTarget
    const ctx = canvas.getContext("2d")
    canvas.width = canvas.clientWidth * ratio
    canvas.height = canvas.clientHeight * ratio
    ctx.setTransform(ratio, 0, 0, ratio, 0, 0)
  }

  startWaveform() {
    if (!this.analyser || !this.hasWaveformTarget) return
    if (this.waveformAnimation) return
    const bufferLength = this.analyser.fftSize
    const dataArray = new Uint8Array(bufferLength)
    const canvas = this.waveformTarget
    const ctx = canvas.getContext("2d")
    const draw = () => {
      this.waveformAnimation = requestAnimationFrame(draw)
      this.analyser.getByteTimeDomainData(dataArray)
      const width = canvas.clientWidth
      const height = canvas.clientHeight
      ctx.clearRect(0, 0, width, height)
      ctx.lineWidth = 2
      ctx.strokeStyle = "#f97316"
      ctx.beginPath()
      const sliceWidth = width / bufferLength
      let x = 0
      for (let i = 0; i < bufferLength; i += 1) {
        const v = dataArray[i] / 128.0
        const y = (v * height) / 2
        if (i === 0) {
          ctx.moveTo(x, y)
        } else {
          ctx.lineTo(x, y)
        }
        x += sliceWidth
      }
      ctx.lineTo(width, height / 2)
      ctx.stroke()
    }
    draw()
  }

  stopWaveform() {
    if (this.waveformAnimation) {
      cancelAnimationFrame(this.waveformAnimation)
      this.waveformAnimation = null
    }
    window.removeEventListener("resize", this.resizeWaveformBound)
  }

  writeToRing(samples, track) {
    if (!this.rings || !samples.length) return

    const maxBufferSamples = Math.floor(this.audioContext.sampleRate * 0.6)
    const ring = this.rings[track] || this.rings.inbound
    for (let i = 0; i < samples.length; i += 1) {
      if (ring.available >= ring.size) {
        ring.read = (ring.read + 1) % ring.size
        ring.available -= 1
      }

      ring.buffer[ring.write] = samples[i]
      ring.write = (ring.write + 1) % ring.size
      ring.available += 1

      if (ring.available > maxBufferSamples) {
        const drop = ring.available - maxBufferSamples
        ring.read = (ring.read + drop) % ring.size
        ring.available = maxBufferSamples
      }
    }
  }

  readFromRing(output) {
    for (let i = 0; i < output.length; i += 1) {
      const inbound = this.readSampleFromRing(this.rings.inbound)
      const outbound = this.readSampleFromRing(this.rings.outbound)
      const mixed = inbound + outbound
      output[i] = Math.max(-1, Math.min(1, mixed))
    }
  }

  readSampleFromRing(ring) {
    if (!ring || ring.available === 0) return 0
    const sample = ring.buffer[ring.read]
    ring.read = (ring.read + 1) % ring.size
    ring.available -= 1
    return sample
  }

  maxAvailable() {
    if (!this.rings) return 0
    return Math.max(this.rings.inbound.available, this.rings.outbound.available)
  }

  resampleToContext(samples, inputRate, outputRate) {
    if (inputRate === outputRate) return samples
    const ratio = outputRate / inputRate
    const newLength = Math.max(1, Math.round(samples.length * ratio))
    const resampled = new Float32Array(newLength)
    for (let i = 0; i < newLength; i += 1) {
      const index = i / ratio
      const left = Math.floor(index)
      const right = Math.min(left + 1, samples.length - 1)
      const frac = index - left
      resampled[i] = samples[left] * (1 - frac) + samples[right] * frac
    }
    return resampled
  }

  decodeMuLaw(base64Payload) {
    const bytes = Uint8Array.from(atob(base64Payload), (c) => c.charCodeAt(0))
    const samples = new Float32Array(bytes.length)
    for (let i = 0; i < bytes.length; i += 1) {
      samples[i] = this.muLawToSample(bytes[i])
    }
    return samples
  }

  muLawToSample(muLawByte) {
    const MU_LAW_BIAS = 0x84
    let uval = (~muLawByte) & 0xff
    let t = ((uval & 0x0f) << 3) + MU_LAW_BIAS
    t <<= (uval & 0x70) >> 4
    const sample = (uval & 0x80) ? MU_LAW_BIAS - t : t - MU_LAW_BIAS
    return Math.max(-1, Math.min(1, sample / 32768))
  }
}
