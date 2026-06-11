//
//  ViewController.swift
//  Examples
//
//  Created by Sondra on 2026/3/23.
//

import UIKit
import SVGAPlayer

class ViewController: UIViewController {

    @IBOutlet weak var imageView: SVGAPlayerView!

    private enum StageState {
        case hidden
        case loading
        case empty
        case error
    }

    private let titleLabel = UILabel()
    private let currentGiftLabel = UILabel()
    private let summaryLabel = PaddedLabel()
    private let stageView = UIView()
    private let playerView = SVGAPlayerView()
    private let stateLabel = UILabel()
    private let sourceBadgeLabel = PaddedLabel()
    private let replayButton = UIButton(type: .system)
    private let pauseButton = UIButton(type: .system)
    private let loopButton = UIButton(type: .system)
    private let searchField = UISearchTextField()
    private let collectionEmptyLabel = UILabel()

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 10
        layout.minimumInteritemSpacing = 10
        layout.sectionInset = UIEdgeInsets(top: 4, left: 0, bottom: 16, right: 0)

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .onDrag
        collectionView.register(GiftEffectCell.self, forCellWithReuseIdentifier: GiftEffectCell.reuseIdentifier)
        collectionView.dataSource = self
        collectionView.delegate = self
        return collectionView
    }()

    private var effects: [GiftEffect] = []
    private var filteredEffects: [GiftEffect] = []
    private var selectedEffect: GiftEffect?
    private var stageState: StageState = .hidden
    private var isLooping = true
    private var isPaused = false

    override func viewDidLoad() {
        super.viewDidLoad()
        imageView?.removeFromSuperview()
        configureLayout()
        configurePlaybackCallbacks()
        loadGiftEffects()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        playerView.stopAnimation()
    }
}

// MARK: - Setup

private extension ViewController {
    func configureLayout() {
        view.backgroundColor = .systemGroupedBackground

        let rootStack = UIStackView()
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.axis = .vertical
        rootStack.spacing = 12
        view.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            rootStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            rootStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            rootStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        let headerStack = makeHeaderStack()
        let controlsStack = makeControlsStack()

        configureStage()
        configureSearchField()
        configureCollectionEmptyLabel()

        rootStack.addArrangedSubview(headerStack)
        rootStack.addArrangedSubview(stageView)
        rootStack.addArrangedSubview(controlsStack)
        rootStack.addArrangedSubview(searchField)
        rootStack.addArrangedSubview(collectionView)

        let stageHeight = stageView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.34)
        stageHeight.priority = .defaultHigh

        NSLayoutConstraint.activate([
            stageHeight,
            stageView.heightAnchor.constraint(greaterThanOrEqualToConstant: 220),
            stageView.heightAnchor.constraint(lessThanOrEqualToConstant: 320),
            controlsStack.heightAnchor.constraint(equalToConstant: 44),
            searchField.heightAnchor.constraint(equalToConstant: 44),
            collectionView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120)
        ])

        setControlsEnabled(false)
    }

    func makeHeaderStack() -> UIStackView {
        titleLabel.text = "礼物特效演示"
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.adjustsFontForContentSizeCategory = true

        summaryLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        summaryLabel.textColor = .white
        summaryLabel.backgroundColor = .systemPink
        summaryLabel.layer.cornerRadius = 10
        summaryLabel.clipsToBounds = true
        summaryLabel.text = "0 个礼物"
        summaryLabel.setContentHuggingPriority(.required, for: .horizontal)

        currentGiftLabel.text = "读取 gift_effects_svga.json"
        currentGiftLabel.font = .systemFont(ofSize: 15, weight: .medium)
        currentGiftLabel.textColor = .secondaryLabel
        currentGiftLabel.numberOfLines = 2

        let titleRow = UIStackView(arrangedSubviews: [titleLabel, UIView(), summaryLabel])
        titleRow.axis = .horizontal
        titleRow.alignment = .center
        titleRow.spacing = 10

        let headerStack = UIStackView(arrangedSubviews: [titleRow, currentGiftLabel])
        headerStack.axis = .vertical
        headerStack.spacing = 4
        return headerStack
    }

    func configureStage() {
        stageView.translatesAutoresizingMaskIntoConstraints = false
        stageView.backgroundColor = UIColor(red: 0.07, green: 0.08, blue: 0.12, alpha: 1)
        stageView.layer.cornerRadius = 8
        stageView.layer.borderWidth = 1
        stageView.layer.borderColor = UIColor.white.withAlphaComponent(0.08).cgColor
        stageView.clipsToBounds = true

        playerView.translatesAutoresizingMaskIntoConstraints = false
        playerView.contentMode = .scaleAspectFit
        playerView.loops = 0
        playerView.clearsAfterStop = true

        stateLabel.translatesAutoresizingMaskIntoConstraints = false
        stateLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        stateLabel.textColor = UIColor.white.withAlphaComponent(0.9)
        stateLabel.textAlignment = .center
        stateLabel.numberOfLines = 0
        stateLabel.isHidden = true

        sourceBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
        sourceBadgeLabel.font = .systemFont(ofSize: 11, weight: .bold)
        sourceBadgeLabel.textColor = .white
        sourceBadgeLabel.backgroundColor = UIColor.white.withAlphaComponent(0.16)
        sourceBadgeLabel.layer.cornerRadius = 9
        sourceBadgeLabel.clipsToBounds = true
        sourceBadgeLabel.text = "SOURCE"

        stageView.addSubview(playerView)
        stageView.addSubview(stateLabel)
        stageView.addSubview(sourceBadgeLabel)

        NSLayoutConstraint.activate([
            playerView.topAnchor.constraint(equalTo: stageView.topAnchor, constant: 8),
            playerView.leadingAnchor.constraint(equalTo: stageView.leadingAnchor, constant: 8),
            playerView.trailingAnchor.constraint(equalTo: stageView.trailingAnchor, constant: -8),
            playerView.bottomAnchor.constraint(equalTo: stageView.bottomAnchor, constant: -8),

            stateLabel.centerXAnchor.constraint(equalTo: stageView.centerXAnchor),
            stateLabel.centerYAnchor.constraint(equalTo: stageView.centerYAnchor),
            stateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: stageView.leadingAnchor, constant: 24),
            stateLabel.trailingAnchor.constraint(lessThanOrEqualTo: stageView.trailingAnchor, constant: -24),

            sourceBadgeLabel.topAnchor.constraint(equalTo: stageView.topAnchor, constant: 12),
            sourceBadgeLabel.trailingAnchor.constraint(equalTo: stageView.trailingAnchor, constant: -12)
        ])
    }

    func makeControlsStack() -> UIStackView {
        configureButton(replayButton, title: "重播", symbolName: "arrow.clockwise", backgroundColor: .systemPink)
        configureButton(pauseButton, title: "暂停", symbolName: "pause.fill", backgroundColor: .systemIndigo)
        configureButton(loopButton, title: "循环", symbolName: "repeat", backgroundColor: .systemTeal)

        replayButton.addTarget(self, action: #selector(replaySelectedGift), for: .touchUpInside)
        pauseButton.addTarget(self, action: #selector(togglePause), for: .touchUpInside)
        loopButton.addTarget(self, action: #selector(toggleLoop), for: .touchUpInside)

        let controlsStack = UIStackView(arrangedSubviews: [replayButton, pauseButton, loopButton])
        controlsStack.axis = .horizontal
        controlsStack.spacing = 10
        controlsStack.distribution = .fillEqually
        return controlsStack
    }

    func configureButton(_ button: UIButton, title: String, symbolName: String, backgroundColor: UIColor) {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.image = UIImage(systemName: symbolName)
        configuration.imagePadding = 6
        configuration.baseBackgroundColor = backgroundColor
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .medium
        button.configuration = configuration
        button.accessibilityLabel = title
    }

    func configureSearchField() {
        searchField.placeholder = "搜索礼物名称或来源"
        searchField.clearButtonMode = .whileEditing
        searchField.returnKeyType = .done
        searchField.autocorrectionType = .no
        searchField.backgroundColor = .secondarySystemGroupedBackground
        searchField.layer.cornerRadius = 8
        searchField.clipsToBounds = true
        searchField.delegate = self
        searchField.addTarget(self, action: #selector(searchTextDidChange), for: .editingChanged)
    }

    func configureCollectionEmptyLabel() {
        collectionEmptyLabel.text = "没有匹配的礼物"
        collectionEmptyLabel.font = .systemFont(ofSize: 14, weight: .medium)
        collectionEmptyLabel.textColor = .secondaryLabel
        collectionEmptyLabel.textAlignment = .center
        collectionEmptyLabel.numberOfLines = 0
    }

    func configurePlaybackCallbacks() {
        playerView.onFrameChanged = { [weak self] _ in
            guard let self, self.stageState == .loading else { return }
            self.hideState()
        }

        playerView.onLoadFailed = { [weak self] _ in
            self?.showState("加载失败\n点击重播重试", state: .error)
        }

        playerView.onFinished = { [weak self] in
            guard let self, !self.isLooping else { return }
            self.isPaused = true
            self.updatePauseButton()
        }
    }
}

// MARK: - Data And Playback

private extension ViewController {
    func loadGiftEffects() {
        do {
            effects = try GiftEffectsDataSource.load()
            filteredEffects = effects
            collectionView.reloadData()
            updateCollectionBackground()
            updateSummary()
            setControlsEnabled(!effects.isEmpty)

            guard let firstEffect = effects.first else {
                currentGiftLabel.text = "暂无礼物资源"
                sourceBadgeLabel.text = "EMPTY"
                showState("JSON 中没有礼物资源", state: .empty)
                return
            }

            play(firstEffect)
        } catch {
            effects = []
            filteredEffects = []
            currentGiftLabel.text = "资源加载失败"
            sourceBadgeLabel.text = "ERROR"
            collectionView.reloadData()
            updateCollectionBackground()
            updateSummary()
            setControlsEnabled(false)
            showState("无法读取 gift_effects_svga.json\n\(error.localizedDescription)", state: .error)
        }
    }

    func play(_ effect: GiftEffect) {
        selectedEffect = effect
        currentGiftLabel.text = effect.name
        sourceBadgeLabel.text = effect.sourceLabel.uppercased()
        isPaused = false
        playerView.loops = isLooping ? 0 : 1
        updatePauseButton()
        updateLoopButton()
        collectionView.reloadData()

        showState("加载中...", state: .loading)
        playerView.clear()
        playerView.play(url: effect.url)
    }

    @objc func replaySelectedGift() {
        guard let selectedEffect else { return }
        play(selectedEffect)
    }

    @objc func togglePause() {
        guard selectedEffect != nil else { return }

        if isPaused {
            playerView.startAnimation()
        } else {
            playerView.pauseAnimation()
        }

        isPaused.toggle()
        updatePauseButton()
    }

    @objc func toggleLoop() {
        isLooping.toggle()
        playerView.loops = isLooping ? 0 : 1
        updateLoopButton()
    }

    @objc func searchTextDidChange() {
        filteredEffects = GiftEffectsDataSource.filter(effects, query: searchField.text ?? "")
        collectionView.reloadData()
        updateCollectionBackground()
        updateSummary()
    }
}

// MARK: - State

private extension ViewController {
    private func showState(_ text: String, state: StageState) {
        stageState = state
        stateLabel.text = text
        stateLabel.isHidden = false

        switch state {
        case .hidden:
            stateLabel.isHidden = true
        case .loading:
            stateLabel.textColor = UIColor.white.withAlphaComponent(0.88)
        case .empty:
            stateLabel.textColor = UIColor.white.withAlphaComponent(0.72)
        case .error:
            stateLabel.textColor = .systemRed
        }
    }

    func hideState() {
        stageState = .hidden
        stateLabel.isHidden = true
    }

    func setControlsEnabled(_ enabled: Bool) {
        replayButton.isEnabled = enabled
        pauseButton.isEnabled = enabled
        loopButton.isEnabled = enabled
        searchField.isEnabled = enabled
        collectionView.isUserInteractionEnabled = enabled
        [replayButton, pauseButton, loopButton].forEach { $0.alpha = enabled ? 1 : 0.45 }
    }

    func updatePauseButton() {
        let title = isPaused ? "继续" : "暂停"
        let symbolName = isPaused ? "play.fill" : "pause.fill"
        configureButton(pauseButton, title: title, symbolName: symbolName, backgroundColor: .systemIndigo)
    }

    func updateLoopButton() {
        let title = isLooping ? "循环" : "一次"
        let symbolName = isLooping ? "repeat" : "repeat.1"
        configureButton(loopButton, title: title, symbolName: symbolName, backgroundColor: isLooping ? .systemTeal : .systemGray)
    }

    func updateSummary() {
        let query = (searchField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            summaryLabel.text = "\(effects.count) 个礼物"
        } else {
            summaryLabel.text = "\(filteredEffects.count)/\(effects.count)"
        }
    }

    func updateCollectionBackground() {
        if filteredEffects.isEmpty {
            collectionEmptyLabel.text = effects.isEmpty ? "暂无礼物资源" : "没有匹配的礼物"
            collectionView.backgroundView = collectionEmptyLabel
        } else {
            collectionView.backgroundView = nil
        }
    }
}

// MARK: - Collection View

extension ViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        filteredEffects.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: GiftEffectCell.reuseIdentifier, for: indexPath)
        guard let giftCell = cell as? GiftEffectCell else { return cell }

        let effect = filteredEffects[indexPath.item]
        giftCell.configure(with: effect, selected: effect == selectedEffect)
        return giftCell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        play(filteredEffects[indexPath.item])
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let layout = collectionViewLayout as? UICollectionViewFlowLayout
        let insets = layout?.sectionInset ?? .zero
        let spacing = layout?.minimumInteritemSpacing ?? 10
        let columns: CGFloat = collectionView.bounds.width >= 430 ? 4 : 3
        let availableWidth = collectionView.bounds.width - insets.left - insets.right - spacing * (columns - 1)
        let width = floor(availableWidth / columns)
        return CGSize(width: width, height: 78)
    }
}

// MARK: - Text Field

extension ViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

// MARK: - Cells

private final class GiftEffectCell: UICollectionViewCell {
    static let reuseIdentifier = "GiftEffectCell"

    private let titleLabel = UILabel()
    private let badgeLabel = PaddedLabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureLayout()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayout()
    }

    override var isHighlighted: Bool {
        didSet {
            contentView.alpha = isHighlighted ? 0.72 : 1
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        badgeLabel.text = nil
        applySelectedStyle(false)
    }

    func configure(with effect: GiftEffect, selected: Bool) {
        titleLabel.text = effect.name
        badgeLabel.text = effect.sourceLabel.uppercased()
        applySelectedStyle(selected)
    }

    private func configureLayout() {
        contentView.layer.cornerRadius = 8
        contentView.layer.borderWidth = 1
        contentView.clipsToBounds = true

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail

        badgeLabel.font = .systemFont(ofSize: 10, weight: .bold)
        badgeLabel.textColor = .secondaryLabel
        badgeLabel.backgroundColor = .tertiarySystemGroupedBackground
        badgeLabel.layer.cornerRadius = 8
        badgeLabel.clipsToBounds = true
        badgeLabel.setContentHuggingPriority(.required, for: .vertical)

        let stack = UIStackView(arrangedSubviews: [titleLabel, badgeLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -10),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -10)
        ])

        applySelectedStyle(false)
    }

    private func applySelectedStyle(_ selected: Bool) {
        contentView.backgroundColor = selected ? UIColor.systemPink.withAlphaComponent(0.14) : .secondarySystemGroupedBackground
        contentView.layer.borderColor = selected ? UIColor.systemPink.cgColor : UIColor.separator.cgColor
        titleLabel.textColor = selected ? .systemPink : .label
        badgeLabel.textColor = selected ? .white : .secondaryLabel
        badgeLabel.backgroundColor = selected ? .systemPink : .tertiarySystemGroupedBackground
    }
}

private final class PaddedLabel: UILabel {
    var contentInsets = UIEdgeInsets(top: 3, left: 8, bottom: 3, right: 8) {
        didSet {
            invalidateIntrinsicContentSize()
            setNeedsDisplay()
        }
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: contentInsets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + contentInsets.left + contentInsets.right,
                      height: size.height + contentInsets.top + contentInsets.bottom)
    }
}
