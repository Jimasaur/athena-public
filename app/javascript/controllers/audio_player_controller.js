import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.audio = this.element.querySelector("audio")
    this.toggle = this.element.querySelector(".audio-toggle")
    this.icon = this.element.querySelector(".audio-icon")
    this.progress = this.element.querySelector(".audio-progress")
    this.currentLabel = this.element.querySelector(".audio-current")
    this.durationLabel = this.element.querySelector(".audio-duration")
    this.errorLabel = this.element.querySelector(".audio-error")
    this.waveform = this.element.querySelector(".audio-waveform")
    this.waveformContext = this.waveform?.getContext("2d") || null
    this.waveformAnimation = null
    this.audioContext = null
    this.analyser = null
    this.source = null

    if (!this.audio || !this.toggle || !this.icon || !this.progress) return

    this.handleToggle = () => {
      if (this.audio.paused) {
        this.clearError()
        this.audio.play().catch((error) => {
          this.showError(error?.message || "The recording could not be played.")
          this.setIcon("play")
        })
      } else {
        this.audio.pause()
      }
    }

    this.handleLoadedMetadata = () => {
      if (this.durationLabel) {
        this.durationLabel.textContent = this.formatTime(this.audio.duration)
      }
    }

    this.handleTimeUpdate = () => {
      if (!this.audio.duration || !this.currentLabel) return
      const percent = (this.audio.currentTime / this.audio.duration) * 100
      this.progress.value = percent.toFixed(2)
      this.currentLabel.textContent = this.formatTime(this.audio.currentTime)
    }

    this.handlePlay = () => {
      this.setIcon("pause")
      this.ensureAnalyser()
      if (this.audioContext?.state === "suspended") {
        this.audioContext.resume()
      }
      this.startWaveform()
    }
    this.handlePause = () => {
      this.setIcon("play")
      this.stopWaveform()
    }
    this.handleEnded = () => {
      this.setIcon("play")
      this.stopWaveform()
    }
    this.handleError = () => {
      this.showError("The recording could not be loaded. Try opening it directly.")
      this.setIcon("play")
      this.stopWaveform()
    }

    this.handleProgress = () => {
      if (!this.audio.duration) return
      const percent = Number(this.progress.value) / 100
      this.audio.currentTime = percent * this.audio.duration
    }

    this.toggle.addEventListener("click", this.handleToggle)
    this.audio.addEventListener("loadedmetadata", this.handleLoadedMetadata)
    this.audio.addEventListener("timeupdate", this.handleTimeUpdate)
    this.audio.addEventListener("play", this.handlePlay)
    this.audio.addEventListener("pause", this.handlePause)
    this.audio.addEventListener("ended", this.handleEnded)
    this.audio.addEventListener("error", this.handleError)
    this.progress.addEventListener("input", this.handleProgress)
    if (this.handleResize) {
      window.addEventListener("resize", this.handleResize)
    }

    this.setIcon("play")
    if (this.audio.readyState >= 1) this.handleLoadedMetadata()
  }

  disconnect() {
    if (!this.audio || !this.toggle || !this.progress) return
    this.toggle.removeEventListener("click", this.handleToggle)
    this.audio.removeEventListener("loadedmetadata", this.handleLoadedMetadata)
    this.audio.removeEventListener("timeupdate", this.handleTimeUpdate)
    this.audio.removeEventListener("play", this.handlePlay)
    this.audio.removeEventListener("pause", this.handlePause)
    this.audio.removeEventListener("ended", this.handleEnded)
    this.audio.removeEventListener("error", this.handleError)
    this.progress.removeEventListener("input", this.handleProgress)
    if (this.handleResize) {
      window.removeEventListener("resize", this.handleResize)
    }
    this.stopWaveform()
    if (this.source) {
      this.source.disconnect()
      this.source = null
    }
    if (this.analyser) {
      this.analyser.disconnect()
      this.analyser = null
    }
    if (this.audioContext) {
      this.audioContext.close()
      this.audioContext = null
    }
  }

  formatTime(seconds) {
    if (!Number.isFinite(seconds)) return "0:00"
    const minutes = Math.floor(seconds / 60)
    const remainder = Math.floor(seconds % 60)
    return `${minutes}:${remainder.toString().padStart(2, "0")}`
  }

  setIcon(state) {
    if (!this.icon) return
    if (state === "pause") {
      this.icon.innerHTML =
        "<rect x='6' y='4' width='4' height='16'></rect><rect x='14' y='4' width='4' height='16'></rect>"
    } else {
      this.icon.innerHTML = "<polygon points='6 4 20 12 6 20 6 4'></polygon>"
    }
  }

  clearError() {
    if (!this.errorLabel) return
    this.errorLabel.textContent = ""
    this.errorLabel.classList.add("hidden")
  }

  showError(message) {
    if (!this.errorLabel) return
    this.errorLabel.textContent = message
    this.errorLabel.classList.remove("hidden")
  }

  ensureAnalyser() {
    if (!this.waveform || !this.audio || this.analyser) return
    const AudioContextClass = window.AudioContext || window.webkitAudioContext
    try {
      this.audioContext = new AudioContextClass()
      this.source = this.audioContext.createMediaElementSource(this.audio)
      this.analyser = this.audioContext.createAnalyser()
      this.analyser.fftSize = 256
      this.source.connect(this.analyser)
      this.analyser.connect(this.audioContext.destination)
      this.handleResize = () => this.resizeWaveform()
      this.resizeWaveform()
      window.addEventListener("resize", this.handleResize)
    } catch (error) {
      this.showError(error?.message || "The waveform could not be initialized.")
    }
  }

  resizeWaveform() {
    if (!this.waveform || !this.waveformContext) return
    const ratio = window.devicePixelRatio || 1
    this.waveform.width = this.waveform.clientWidth * ratio
    this.waveform.height = this.waveform.clientHeight * ratio
    this.waveformContext.setTransform(ratio, 0, 0, ratio, 0, 0)
  }

  startWaveform() {
    if (!this.waveform || !this.analyser || this.waveformAnimation) return
    const bufferLength = this.analyser.fftSize
    const dataArray = new Uint8Array(bufferLength)
    const ctx = this.waveformContext
    const draw = () => {
      this.waveformAnimation = requestAnimationFrame(draw)
      this.analyser.getByteTimeDomainData(dataArray)
      const width = this.waveform.clientWidth
      const height = this.waveform.clientHeight
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
  }
}
