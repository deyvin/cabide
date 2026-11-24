import { Controller } from "@hotwired/stimulus"

// Opens/closes <dialog> elements by id: data-action="dialog#open" data-dialog-id-param="new-garment"
export default class extends Controller {
  open({ params: { id } }) {
    document.getElementById(id)?.showModal()
  }

  close(event) {
    event.target.closest("dialog")?.close()
  }
}
