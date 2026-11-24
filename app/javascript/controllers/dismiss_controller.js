import { Controller } from "@hotwired/stimulus"

// Flash messages that fade away on their own.
export default class extends Controller {
  static values = { after: Number }

  connect() {
    if (this.afterValue) this.timer = setTimeout(() => this.close(), this.afterValue)
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  close() {
    this.element.style.transition = "opacity .3s"
    this.element.style.opacity = "0"
    setTimeout(() => this.element.remove(), 300)
  }
}
