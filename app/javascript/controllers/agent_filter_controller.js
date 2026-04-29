import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu", "label", "input"]

  connect() {
    this.handleOutsideClick = this.handleOutsideClick.bind(this)
    document.addEventListener("click", this.handleOutsideClick)
  }

  disconnect() {
    document.removeEventListener("click", this.handleOutsideClick)
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()
    this.menuTarget.classList.toggle("hidden")
  }

  select(event) {
    event.preventDefault()
    event.stopPropagation()
    const value = event.currentTarget.dataset.value || ""
    this.labelTarget.textContent = event.currentTarget.textContent.trim()
    this.inputTarget.value = value
    this.close()
    const form = this.element.closest("form")
    if (form?.requestSubmit) {
      form.requestSubmit()
    } else if (form) {
      form.submit()
    }
  }

  close() {
    this.menuTarget.classList.add("hidden")
  }

  handleOutsideClick(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }
}
