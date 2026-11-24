import { Controller } from "@hotwired/stimulus"

// Shows a thumbnail of the chosen photo inside its drop zone.
// HEIC can't be previewed by most browsers, so we fall back to the file name.
export default class extends Controller {
  static targets = ["input", "image", "placeholder", "name"]

  show() {
    const file = this.inputTarget.files[0]
    if (!file) return

    this.nameTarget.textContent = file.name
    this.nameTarget.classList.remove("hidden")

    const heic = /\.(heic|heif)$/i.test(file.name) || /hei[cf]/.test(file.type)
    if (heic) {
      this.imageTarget.classList.add("hidden")
      this.placeholderTarget.classList.remove("hidden")
      return
    }

    this.imageTarget.src = URL.createObjectURL(file)
    this.imageTarget.classList.remove("hidden")
    this.placeholderTarget.classList.add("hidden")
  }
}
