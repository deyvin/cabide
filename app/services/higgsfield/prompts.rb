module Higgsfield
  # Prompts proven in the hoodie test: ghost-mannequin catalog shots on a white
  # background, then a UGC try-on video built from those catalog shots.
  module Prompts
    CATALOG_COMMON = <<~TEXT.squish
      Pure white seamless background (#FFFFFF), soft even studio lighting, very subtle contact shadow,
      wrinkle-free, realistic fabric texture, true-to-life colors, centered composition, high resolution,
      sharp focus. No mannequin visible, no body, no skin, no hanger, no floor, no props, no extra text.
    TEXT

    module_function

    def catalog(side, instructions: nil)
      view = side.to_s == "back" ? "back" : "front"
      <<~TEXT.squish
        Professional e-commerce catalog product photo of this exact garment in ghost mannequin style
        (invisible mannequin), #{view} view, the garment shown with natural 3D volume as if worn by an
        invisible body, shoulders and #{view == "back" ? "back" : "chest"} filled out, sleeves (if any)
        hanging naturally at the sides, #{view == "front" ? "closures such as zippers or buttons neatly closed, " : ""}centered.
        Keep every print, logo, embroidery, text, label and color exactly as in the reference photo:
        same size, position, font and spelling, crisp and legible. Each print stays on the exact area of
        the garment where it is in the reference (for example left or right chest, center back); never move
        a print to another area such as the hem, pocket or sleeves. Remove everything around the garment
        from the original photo (floor, rugs, furniture, objects).
        #{CATALOG_COMMON}#{user_notes(instructions)}
      TEXT
    end

    def ugc_video(garment_names:, instructions: nil)
      look = garment_names.size == 1 ? "this exact garment" : "this exact outfit made of these garments"
      pieces = garment_names.many? ? " (#{garment_names.to_sentence(locale: :en)})" : ""
      <<~TEXT.squish
        Authentic UGC-style vertical video filmed on a smartphone. A stylish young Brazilian person in
        their mid-20s, casual streetwear vibe, wearing #{look}#{pieces} from the reference images.
        They stand in a bright, modern apartment with natural window light. They hold the phone at arm's
        length like a selfie, smile at the camera and show the front of the outfit, pointing at its details,
        then turn around slowly to show the back, look back over their shoulder at the camera with a
        confident grin and give a thumbs up. Keep every garment exactly as in the references: same colors,
        fit, prints, fonts, logos and positions, text crisp and legible. Natural handheld camera shake,
        casual and genuine energy, realistic skin and fabric texture, soft natural lighting, social-media
        try-on haul aesthetic. No on-screen text, no logos other than the garment prints, no distortion
        of the lettering.#{user_notes(instructions)}
      TEXT
    end

    # Notes typed by the user when regenerating; they win over the defaults above.
    def user_notes(instructions)
      notes = instructions.to_s.squish.truncate(500)
      notes.present? ? " Additional instructions from the user (highest priority, follow them exactly): #{notes}" : ""
    end
  end
end
