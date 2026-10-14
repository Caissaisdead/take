import UIKit

/// The row above the keyboard: italics, bold, a note, a scene break, a jump
/// to the paragraph before or after, and Done. Nothing else: the phone is
/// for lines, not formatting.
final class EditorAccessoryBar: UIInputView {
    private weak var host: ProseUITextView?

    init(host: ProseUITextView) {
        self.host = host
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 44), inputViewStyle: .keyboard)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private func build() {
        let stack = UIStackView(arrangedSubviews: [
            button(title: "*", action: #selector(italic)),
            button(title: "**", action: #selector(bold)),
            button(title: "[[ ]]", action: #selector(note)),
            button(title: "* * *", action: #selector(sceneBreak)),
            button(symbol: "chevron.up", action: #selector(previousParagraph)),
            button(symbol: "chevron.down", action: #selector(nextParagraph)),
            UIView(),
            button(title: "Done", action: #selector(done), bold: true),
        ])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        if let spacer = stack.arrangedSubviews.first(where: { !($0 is UIButton) }) {
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }
    }

    private func button(title: String? = nil, symbol: String? = nil, action: Selector, bold: Bool = false) -> UIButton {
        var config = UIButton.Configuration.plain()
        if let title {
            config.attributedTitle = AttributedString(title, attributes: AttributeContainer([
                .font: UIFont.monospacedSystemFont(ofSize: 15, weight: bold ? .semibold : .regular),
            ]))
        }
        if let symbol {
            config.image = UIImage(systemName: symbol)
        }
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
        let button = UIButton(configuration: config)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    @objc private func italic() { host?.wrapSelection(in: "*") }
    @objc private func bold() { host?.wrapSelection(in: "**") }
    @objc private func note() { host?.insertNote() }
    @objc private func sceneBreak() { host?.insertSceneBreak() }
    @objc private func previousParagraph() { host?.moveToParagraph(.previous) }
    @objc private func nextParagraph() { host?.moveToParagraph(.next) }
    @objc private func done() { host?.resignFirstResponder() }
}
