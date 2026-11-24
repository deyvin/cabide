import { Controller } from "@hotwired/stimulus"

// Picks garments for a video. Selection survives live re-renders of the cards
// (Turbo Stream broadcasts) because it lives here, not in the card markup.
export default class extends Controller {
  static targets = ["garment", "bar", "form", "inputs", "count", "hint", "submit"]
  static values = { maxImages: Number }

  connect() {
    this.selected = new Set()
    this.render()
  }

  toggle(event) {
    const id = event.currentTarget.dataset.garmentId
    this.selected.has(id) ? this.selected.delete(id) : this.selected.add(id)
    this.render()
  }

  clear() {
    this.selected.clear()
    this.render()
  }

  // A card was (re)rendered by a broadcast: re-apply its state.
  garmentTargetConnected() {
    if (this.selected) this.render()
  }

  // A card was removed: forget it if it no longer exists.
  garmentTargetDisconnected() {
    if (!this.selected) return
    requestAnimationFrame(() => {
      const present = new Set(this.garmentTargets.map((el) => el.dataset.garmentId))
      for (const id of this.selected) if (!present.has(id)) this.selected.delete(id)
      this.render()
    })
  }

  render() {
    let images = 0
    for (const card of this.garmentTargets) {
      const id = card.dataset.garmentId
      if (this.selected.has(id) && card.dataset.ready !== "true") this.selected.delete(id)
      const on = this.selected.has(id)
      card.dataset.selected = on
      card.querySelector("[aria-pressed]")?.setAttribute("aria-pressed", on)
      if (on) images += Number(card.dataset.images || 1)
    }

    const count = this.selected.size
    this.barTarget.hidden = count === 0
    this.countTarget.textContent = count === 1 ? "1 peça" : `${count} peças`

    const tooMany = images > this.maxImagesValue
    this.submitTarget.disabled = count === 0 || tooMany
    this.hintTarget.textContent = tooMany
      ? `Máximo de ${this.maxImagesValue} fotos por vídeo — tire alguma peça`
      : "Um vídeo com alguém vestindo tudo junto"

    this.inputsTarget.replaceChildren(
      ...[...this.selected].map((id) => Object.assign(document.createElement("input"), { type: "hidden", name: "garment_ids[]", value: id }))
    )
  }
}
