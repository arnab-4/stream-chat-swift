//
// Copyright © 2023 Stream.io Inc. All rights reserved.
//

import StreamChat
import UIKit

/// A `UIViewController` subclass  that shows list of channels.
@available(iOSApplicationExtension, unavailable)
open class ChatChannelListVC: _ViewController,
    UICollectionViewDataSource,
    UICollectionViewDelegate,
    ChatChannelListControllerDelegate,
    DataControllerStateDelegate,
    ThemeProvider,
    SwipeableViewDelegate {
    /// The `ChatChannelListController` instance that provides channels data.
    public var controller: ChatChannelListController!

    private var isPaginatingChannels: Bool = false

    /// A boolean value that determines if the chat channel list view states are shown and handled by the SDK.
    open var isChatChannelListStatesEnabled: Bool {
        components.isChatChannelListStatesEnabled
    }

    open private(set) lazy var loadingIndicator: UIActivityIndicatorView = {
        if #available(iOS 13.0, *) {
            return UIActivityIndicatorView(style: .large).withoutAutoresizingMaskConstraints
        } else {
            return UIActivityIndicatorView(style: .whiteLarge).withoutAutoresizingMaskConstraints
        }
    }()

    /// A router object responsible for handling navigation actions of this view controller.
    open lazy var router: ChatChannelListRouter = components
        .channelListRouter
        .init(rootViewController: self)

    /// The `UICollectionViewLayout` that used by `ChatChannelListCollectionView`.
    open private(set) lazy var collectionViewLayout: UICollectionViewLayout = components
        .channelListLayout.init()

    /// The `UICollectionView` instance that displays channel list.
    open private(set) lazy var collectionView: UICollectionView =
        UICollectionView(frame: .zero, collectionViewLayout: collectionViewLayout)
            .withoutAutoresizingMaskConstraints
            .withAccessibilityIdentifier(identifier: "collectionView")

    /// The view that is displayed when there are no channels on the list, i.e. when is on empty state.
    open lazy var emptyView: ChatChannelListEmptyView = components.channelListEmptyView.init()
        .withoutAutoresizingMaskConstraints

    /// View which will be shown at the bottom when an error occurs when fetching either local or remote channels.
    /// This view has an action to retry the channel loading.
    open private(set) lazy var channelListErrorView: ChatChannelListErrorView = {
        let view = components.channelListErrorView.init()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()

    /// View that shows when loading the Channel list.
    open private(set) lazy var chatChannelListLoadingView: ChatChannelListLoadingView = components
        .chatChannelListLoadingView
        .init()
        .withoutAutoresizingMaskConstraints

    /// The `CurrentChatUserAvatarView` instance used for displaying avatar of the current user.
    open private(set) lazy var userAvatarView: CurrentChatUserAvatarView = components
        .currentUserAvatarView.init()
        .withoutAutoresizingMaskConstraints

    /// Reuse identifier of separator
    open var separatorReuseIdentifier: String { "CellSeparatorIdentifier" }

    /// Reuse identifier of `collectionViewCell`
    open var collectionViewCellReuseIdentifier: String { String(describing: ChatChannelListCollectionViewCell.self) }

    /// Component responsible to process an array of `[ListChange<Item>]`'s and apply those changes to a view.
    private lazy var listChangeUpdater: ListChangeUpdater = CollectionViewListChangeUpdater(
        collectionView: collectionView
    )

    /// Currently there are some performance problems in the Channel List which
    /// is impacting the message list performance as well, so we skip channel list
    /// updates when the channel list is not visible in the window.
    private(set) var skippedRendering = false

    /// Create a new `ChatChannelListViewController`
    /// - Parameters:
    ///   - controller: Your created `ChatChannelListController` with required query
    ///   - storyboard: The storyboard to instantiate your `ViewController` from
    ///   - storyboardId: The `storyboardId` that is set in your `UIStoryboard` reference
    /// - Returns: A newly created `ChatChannelListViewController`
    public static func make(
        with controller: ChatChannelListController,
        storyboard: UIStoryboard? = nil,
        storyboardId: String? = nil
    ) -> Self {
        var chatChannelListVC: Self!

        // Check if we have a UIStoryboard and/or StoryboardId
        if let storyboardId = storyboardId, let storyboard = storyboard {
            // Safely unwrap the ViewController from the Storyboard
            guard let localViewControllerFromStoryboard = storyboard
                .instantiateViewController(withIdentifier: storyboardId) as? Self else {
                fatalError("Failed to load from UIStoryboard, please check your storyboardId and/or UIStoryboard reference.")
            }
            chatChannelListVC = localViewControllerFromStoryboard
        } else {
            chatChannelListVC = Self()
        }

        // Set the Controller on the ViewController
        chatChannelListVC.controller = controller

        // Return the newly created ChatChannelListVC
        return chatChannelListVC
    }

    override open func setUp() {
        super.setUp()
        controller.delegate = self
        controller.synchronize()

        collectionView.register(
            components.channelCell.self,
            forCellWithReuseIdentifier: collectionViewCellReuseIdentifier
        )

        collectionView.register(
            components.channelCellSeparator,
            forSupplementaryViewOfKind: ListCollectionViewLayout.separatorKind,
            withReuseIdentifier: separatorReuseIdentifier
        )

        collectionView.dataSource = self
        collectionView.delegate = self

        userAvatarView.controller = controller.client.currentUserController()
        userAvatarView.addTarget(self, action: #selector(didTapOnCurrentUserAvatar), for: .touchUpInside)

        channelListErrorView.refreshButtonAction = { [weak self] in
            self?.controller.synchronize()
            self?.channelListErrorView.hide()
        }
    }

    override open func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if skippedRendering {
            collectionView.reloadData()
            skippedRendering = false
        }
    }

    open func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        if controller.state != .remoteDataFetched {
            return
        }

        guard collectionView.isTrackingOrDecelerating else {
            return
        }

        if indexPath.row < collectionView.numberOfItems(inSection: 0) - 10 {
            return
        }

        loadMoreChannels()
    }

    override open func setUpLayout() {
        super.setUpLayout()
        view.embed(collectionView)

        if isChatChannelListStatesEnabled {
            view.embed(chatChannelListLoadingView)
            view.embed(emptyView)
            emptyView.isHidden = true
            view.addSubview(channelListErrorView)
            channelListErrorView.pin(anchors: [.leading, .trailing, .bottom], to: view)
            channelListErrorView.hide()
        } else {
            collectionView.addSubview(loadingIndicator)
            loadingIndicator.pin(anchors: [.centerX, .centerY], to: view)
        }
    }

    override open func setUpAppearance() {
        super.setUpAppearance()
        title = "Stream Chat"

        navigationItem.backButtonTitle = ""
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: userAvatarView)

        collectionView.backgroundColor = appearance.colorPalette.background

        if let flowLayout = collectionViewLayout as? ListCollectionViewLayout {
            flowLayout.itemSize = UICollectionViewFlowLayout.automaticSize
            flowLayout.estimatedItemSize = .init(
                width: collectionView.bounds.width,
                height: 64
            )
        }
    }

    override open func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        chatChannelListLoadingView.updateContent()
    }

    open func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        controller.channels.count
    }

    open func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(with: ChatChannelListCollectionViewCell.self, for: indexPath)
        guard let channel = getChannel(at: indexPath) else { return cell }

        cell.components = components
        cell.itemView.content = .init(channel: channel, currentUserId: controller.client.currentUserId)

        cell.swipeableView.delegate = self
        cell.swipeableView.indexPath = { [weak cell, weak self] in
            guard let cell = cell else { return nil }
            return self?.collectionView.indexPath(for: cell)
        }

        return cell
    }

    open func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        collectionView.dequeueReusableSupplementaryView(
            ofKind: ListCollectionViewLayout.separatorKind,
            withReuseIdentifier: separatorReuseIdentifier,
            for: indexPath
        )
    }

    open func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        defer {
            collectionView.deselectItem(at: indexPath, animated: true)
        }
        guard let channel = getChannel(at: indexPath) else { return }
        router.showChannel(for: channel.cid)
    }

    @objc open func didTapOnCurrentUserAvatar(_ sender: Any) {
        router.showCurrentUserProfile()
    }

    override open func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        collectionViewLayout.invalidateLayout()

        // Required to correctly setup navigation when view is wrapped
        // using UIHostingController and used in SwiftUI
        guard
            let parent = parent,
            parent.isUIHostingController
        else { return }

        if #available(iOS 13.0, *) {
            setupParentNavigation(parent: parent)
        }
    }

    open func loadMoreChannels() {
        guard !isPaginatingChannels else {
            return
        }
        isPaginatingChannels = true

        controller.loadNextChannels { [weak self] _ in
            self?.isPaginatingChannels = false
        }
    }

    open func swipeableViewWillShowActionViews(for indexPath: IndexPath) {
        // Close other open cells
        collectionView.visibleCells.forEach {
            let cell = ($0 as? ChatChannelListCollectionViewCell)
            cell?.swipeableView.close()
        }

        Animate { self.collectionView.layoutIfNeeded() }
    }

    open func swipeableViewActionViews(for indexPath: IndexPath) -> [UIView] {
        let deleteView = CellActionView()
            .withoutAutoresizingMaskConstraints
            .withAccessibilityIdentifier(identifier: "deleteView")
        deleteView.actionButton.setImage(appearance.images.messageActionDelete, for: .normal)

        deleteView.actionButton.backgroundColor = appearance.colorPalette.alert
        deleteView.actionButton.tintColor = .white

        deleteView.action = { [weak self] in self?.deleteButtonPressedForCell(at: indexPath) }

        let moreView = CellActionView()
            .withoutAutoresizingMaskConstraints
            .withAccessibilityIdentifier(identifier: "moreView")
        moreView.actionButton.setImage(appearance.images.more, for: .normal)

        moreView.actionButton.backgroundColor = appearance.colorPalette.background1
        moreView.actionButton.tintColor = appearance.colorPalette.text

        moreView.action = { [weak self] in self?.moreButtonPressedForCell(at: indexPath) }

        return [moreView, deleteView]
    }

    /// This function is called when delete button is pressed from action items of a cell.
    /// - Parameter indexPath: IndexPath of given cell to fetch the content of it.
    open func deleteButtonPressedForCell(at indexPath: IndexPath) {
        guard let channel = getChannel(at: indexPath) else { return }
        router.didTapDeleteButton(for: channel.cid)
    }

    /// This function is called when more button is pressed from action items of a cell.
    /// - Parameter indexPath: IndexPath of given cell to fetch the content of it.
    open func moreButtonPressedForCell(at indexPath: IndexPath) {
        guard let channel = getChannel(at: indexPath) else { return }
        router.didTapMoreButton(for: channel.cid)
    }

    // MARK: - ChatChannelListControllerDelegate

    open func controllerWillChangeChannels(_ controller: ChatChannelListController) {
        collectionView.layoutIfNeeded()
    }

    open func controller(
        _ controller: ChatChannelListController,
        didChangeChannels changes: [ListChange<ChatChannel>]
    ) {
        let isViewNotVisible = viewIfLoaded?.window == nil
        if isViewNotVisible {
            skippedRendering = true
            return
        }

        listChangeUpdater.performUpdate(with: changes)
    }

    @available(*, deprecated, message: "Please use `filter` when initializing a `ChatChannelListController`")
    open func controller(_ controller: ChatChannelListController, shouldAddNewChannelToList channel: ChatChannel) -> Bool {
        channel.membership != nil
    }

    @available(*, deprecated, message: "Please use `filter` when initializing a `ChatChannelListController`")
    open func controller(_ controller: ChatChannelListController, shouldListUpdatedChannel channel: ChatChannel) -> Bool {
        channel.membership != nil
    }

    // MARK: - DataControllerStateDelegate

    open func controller(_ controller: DataController, didChangeState state: DataController.State) {
        if isChatChannelListStatesEnabled {
            var shouldHideEmptyView = true
            var isLoading = true

            switch state {
            case .initialized, .localDataFetched:
                isLoading = self.controller.channels.isEmpty
            case .remoteDataFetched:
                isLoading = false
                shouldHideEmptyView = !self.controller.channels.isEmpty
            case .localDataFetchFailed, .remoteDataFetchFailed:
                shouldHideEmptyView = emptyView.isHidden
                isLoading = false
                channelListErrorView.show()
            }

            emptyView.isHidden = shouldHideEmptyView
            chatChannelListLoadingView.isHidden = !isLoading
        } else {
            switch state {
            case .initialized, .localDataFetched:
                if self.controller.channels.isEmpty {
                    loadingIndicator.startAnimating()
                } else {
                    loadingIndicator.stopAnimating()
                }
            default:
                loadingIndicator.stopAnimating()
            }
        }
    }

    private func getChannel(at indexPath: IndexPath) -> ChatChannel? {
        let index = indexPath.row
        controller.channels.assertIndexIsPresent(index)
        return controller.channels[safe: index]
    }
}
