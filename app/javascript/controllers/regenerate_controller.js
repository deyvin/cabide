import { Controller } from "@hotwired/stimulus"

// Opens the shared "Gerar de novo" dialog for a photo (front/back choice) or a video.
// Each option is { label, url, instructions } and becomes a radio that sets the form action.
export default class extends Controller {
  static targets = ["dialog", "form", "title", "choices", "options", "instructions", "submit"]

  open({ params: { title, kind, options } }) {
    this.titleTarget.textContent = title
    this.choicesTarget.hidden = options.length < 2 && kind === "video"

    this.optionsTarget.replaceChildren(...options.map((option, index) => this.radio(option, index === 0)))
    this.select(options[0])
    this.submitTarget.textContent = kind === "video" ? "Gravar de novo" : "Gerar de novo"

    this.dialogTarget.showModal()
    this.instructionsTarget.focus()
  }

  radio(option, checked) {
    const label = document.createElement("label")
    label.className = "cursor-pointer"
    label.innerHTML = `
      <input type="radio" name="regenerate_choice" class="peer sr-only">
      <span class="block rounded-full border border-ink/15 px-4 py-2 text-sm transition peer-checked:border-ink peer-checked:bg-ink peer-checked:text-paper peer-focus-visible:ring-2 peer-focus-visible:ring-ink"></span>`
    label.querySelector("span").textContent = option.label
    const input = label.querySelector("input")
    input.checked = checked
    input.addEventListener("change", () => this.select(option))
    return label
  }

  select(option) {
    this.formTarget.action = option.url
    this.instructionsTarget.value = option.instructions || ""
  }
}
