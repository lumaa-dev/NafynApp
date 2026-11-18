// Made by Lumaa

import SwiftUI

struct PillTextFieldStyle: TextFieldStyle {
	func _body(configuration: TextField<Self._Label>) -> some View {
		configuration
			.font(DTFont.system(18))
			.foregroundStyle(DTColor.textPrimary)
			.padding(.vertical, DTSpacing.inputVertical)
			.padding(.horizontal, DTSpacing.inputHorizontal)
			.background(DTColor.surfaceInput, in: Capsule())
	}
}

extension TextFieldStyle where Self == PillTextFieldStyle {
	static var pill: PillTextFieldStyle { PillTextFieldStyle() }
}
