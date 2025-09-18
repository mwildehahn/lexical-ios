/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import UIKit

final class InfoOverlayViewController: UIViewController {

  private let message: String

  init(title: String, message: String) {
    self.message = message
    super.init(nibName: nil, bundle: nil)
    self.title = title
    modalPresentationStyle = .pageSheet
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground

    let label = UILabel()
    label.numberOfLines = 0
    label.font = UIFont.preferredFont(forTextStyle: .body)
    label.text = message
    label.translatesAutoresizingMaskIntoConstraints = false

    let closeButton = UIButton(type: .system)
    closeButton.setTitle("Done", for: .normal)
    closeButton.addTarget(self, action: #selector(dismissSelf), for: .touchUpInside)
    closeButton.translatesAutoresizingMaskIntoConstraints = false

    view.addSubview(label)
    view.addSubview(closeButton)

    NSLayoutConstraint.activate([
      label.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
      label.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
      label.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),

      closeButton.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 20),
      closeButton.centerXAnchor.constraint(equalTo: view.centerXAnchor)
    ])
  }

  @objc private func dismissSelf() {
    dismiss(animated: true)
  }
}

