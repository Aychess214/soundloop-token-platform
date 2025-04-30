;; sound-loop-token
;; A contract that manages the creation, ownership, and trading of unique audio assets
;; on the SoundLoop platform. Each token represents a distinct sound creation with its
;; associated metadata and ownership information.

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-TOKEN-NOT-FOUND (err u101))
(define-constant ERR-ALREADY-LISTED (err u102))
(define-constant ERR-NOT-LISTED (err u103))
(define-constant ERR-INVALID-PRICE (err u104))
(define-constant ERR-UNAUTHORIZED-TRANSFER (err u105))
(define-constant ERR-CANNOT-BUY-OWN-TOKEN (err u106))
(define-constant ERR-INSUFFICIENT-FUNDS (err u107))
(define-constant ERR-COLLECTION-NOT-FOUND (err u108))
(define-constant ERR-TOKEN-ALREADY-IN-COLLECTION (err u109))
(define-constant ERR-TOKEN-NOT-IN-COLLECTION (err u110))
(define-constant ERR-INVALID-ROYALTY (err u111))
(define-constant ERR-COLLECTION-LIMIT-EXCEEDED (err u112))

;; Data space definitions

;; Token data storage
(define-map tokens
  { token-id: uint }
  {
    owner: principal,
    creator: principal,
    title: (string-utf8 100),
    description: (string-utf8 500),
    audio-url: (string-utf8 256),
    audio-length: uint,
    creation-date: uint,
    royalty-percentage: uint,
    is-listed: bool,
    price: uint
  }
)

;; Collection data storage
(define-map collections
  { collection-id: uint }
  {
    name: (string-utf8 100),
    description: (string-utf8 500),
    creator: principal,
    creation-date: uint,
    token-ids: (list 100 uint)
  }
)

;; Mapping of token to its provenance history
(define-map token-provenance
  { token-id: uint }
  { history: (list 50 { owner: principal, acquired-at: uint, price: uint }) }
)

;; Ownership index for efficient lookup
(define-map owner-tokens
  { owner: principal }
  { token-ids: (list 1000 uint) }
)

;; Counter for token IDs
(define-data-var next-token-id uint u1)

;; Counter for collection IDs
(define-data-var next-collection-id uint u1)

;; Private functions

;; Add a token ID to an owner's list of tokens
(define-private (add-token-to-owner (token-id uint) (owner principal))
  (let ((current-tokens (default-to { token-ids: (list) } (map-get? owner-tokens { owner: owner }))))
    (map-set owner-tokens
      { owner: owner }
      { token-ids: (append (get token-ids current-tokens) token-id) })
  )
)

;; Remove a token ID from an owner's list of tokens
(define-private (remove-token-from-owner (token-id uint) (owner principal))
  (let ((current-tokens (default-to { token-ids: (list) } (map-get? owner-tokens { owner: owner }))))
    (map-set owner-tokens
      { owner: owner }
      { token-ids: (filter remove-token-filter (get token-ids current-tokens)) })
  )
  (where remove-token-filter (id) (not (is-eq id token-id)))
)

;; Check if a token exists and return boolean
(define-private (token-exists (token-id uint))
  (is-some (map-get? tokens { token-id: token-id }))
)

;; Check token ownership
(define-private (is-token-owner (token-id uint) (address principal))
  (let ((token-data (map-get? tokens { token-id: token-id })))
    (and 
      (is-some token-data)
      (is-eq address (get owner (unwrap-panic token-data)))
    )
  )
)

;; Add entry to token provenance
(define-private (add-provenance-entry (token-id uint) (new-owner principal) (price uint))
  (let (
    (current-provenance (default-to { history: (list) } (map-get? token-provenance { token-id: token-id })))
    (new-entry { owner: new-owner, acquired-at: block-height, price: price })
  )
    (map-set token-provenance
      { token-id: token-id }
      { history: (append (get history current-provenance) new-entry) }
    )
  )
)

;; Transfer royalty payment to creator
(define-private (pay-royalty (token-id uint) (sale-price uint))
  (let (
    (token-data (unwrap-panic (map-get? tokens { token-id: token-id })))
    (creator (get creator token-data))
    (royalty-percentage (get royalty-percentage token-data))
    (royalty-amount (/ (* sale-price royalty-percentage) u100))
  )
    (if (> royalty-amount u0)
      (stx-transfer? royalty-amount tx-sender creator)
      (ok true))
  )
)

;; Read-only functions

;; Get token information
(define-read-only (get-token (token-id uint))
  (map-get? tokens { token-id: token-id })
)

;; Get token provenance history
(define-read-only (get-token-provenance (token-id uint))
  (map-get? token-provenance { token-id: token-id })
)

;; Get collection information
(define-read-only (get-collection (collection-id uint))
  (map-get? collections { collection-id: collection-id })
)

;; Get tokens owned by a specific address
(define-read-only (get-owner-tokens (owner principal))
  (default-to { token-ids: (list) } (map-get? owner-tokens { owner: owner }))
)

;; Check if a token is listed for sale
(define-read-only (is-token-listed (token-id uint))
  (let ((token-data (map-get? tokens { token-id: token-id })))
    (match token-data
      token-info (get is-listed token-info)
      false
    )
  )
)

;; Get the current market price of a token
(define-read-only (get-token-price (token-id uint))
  (let ((token-data (map-get? tokens { token-id: token-id })))
    (match token-data
      token-info (get price token-info)
      u0
    )
  )
)

;; Public functions

;; Mint a new audio token
(define-public (mint-token 
  (title (string-utf8 100)) 
  (description (string-utf8 500)) 
  (audio-url (string-utf8 256)) 
  (audio-length uint)
  (royalty-percentage uint)
)
  (let (
    (token-id (var-get next-token-id))
    (creator tx-sender)
  )
    ;; Check for valid royalty percentage (0-30%)
    (asserts! (<= royalty-percentage u30) ERR-INVALID-ROYALTY)
    
    ;; Create the token
    (map-set tokens
      { token-id: token-id }
      {
        owner: creator,
        creator: creator,
        title: title,
        description: description,
        audio-url: audio-url,
        audio-length: audio-length,
        creation-date: block-height,
        royalty-percentage: royalty-percentage,
        is-listed: false,
        price: u0
      }
    )
    
    ;; Update the token ID counter
    (var-set next-token-id (+ token-id u1))
    
    ;; Add token to owner's list
    (add-token-to-owner token-id creator)
    
    ;; Initialize token provenance
    (add-provenance-entry token-id creator u0)
    
    (ok token-id)
  )
)

;; Transfer token from one user to another
(define-public (transfer-token (token-id uint) (recipient principal))
  (let ((token-data (unwrap! (map-get? tokens { token-id: token-id }) ERR-TOKEN-NOT-FOUND)))
    ;; Check ownership
    (asserts! (is-eq tx-sender (get owner token-data)) ERR-NOT-AUTHORIZED)
    ;; Check that token is not listed for sale
    (asserts! (not (get is-listed token-data)) ERR-ALREADY-LISTED)
    
    ;; Update owner in token data
    (map-set tokens
      { token-id: token-id }
      (merge token-data { owner: recipient })
    )
    
    ;; Update ownership records
    (remove-token-from-owner token-id tx-sender)
    (add-token-to-owner token-id recipient)
    
    ;; Add to provenance history
    (add-provenance-entry token-id recipient u0)
    
    (ok true)
  )
)

;; List token for sale
(define-public (list-token (token-id uint) (price uint))
  (let ((token-data (unwrap! (map-get? tokens { token-id: token-id }) ERR-TOKEN-NOT-FOUND)))
    ;; Check ownership
    (asserts! (is-eq tx-sender (get owner token-data)) ERR-NOT-AUTHORIZED)
    ;; Check that token is not already listed
    (asserts! (not (get is-listed token-data)) ERR-ALREADY-LISTED)
    ;; Check for valid price
    (asserts! (> price u0) ERR-INVALID-PRICE)
    
    ;; Update token to listed status with price
    (map-set tokens
      { token-id: token-id }
      (merge token-data { is-listed: true, price: price })
    )
    
    (ok true)
  )
)

;; Unlist token from sale
(define-public (unlist-token (token-id uint))
  (let ((token-data (unwrap! (map-get? tokens { token-id: token-id }) ERR-TOKEN-NOT-FOUND)))
    ;; Check ownership
    (asserts! (is-eq tx-sender (get owner token-data)) ERR-NOT-AUTHORIZED)
    ;; Check that token is listed
    (asserts! (get is-listed token-data) ERR-NOT-LISTED)
    
    ;; Update token to unlisted status
    (map-set tokens
      { token-id: token-id }
      (merge token-data { is-listed: false, price: u0 })
    )
    
    (ok true)
  )
)

;; Purchase a listed token
(define-public (buy-token (token-id uint))
  (let (
    (token-data (unwrap! (map-get? tokens { token-id: token-id }) ERR-TOKEN-NOT-FOUND))
    (seller (get owner token-data))
    (price (get price token-data))
  )
    ;; Check that token is listed for sale
    (asserts! (get is-listed token-data) ERR-NOT-LISTED)
    ;; Cannot buy your own token
    (asserts! (not (is-eq tx-sender seller)) ERR-CANNOT-BUY-OWN-TOKEN)
    
    ;; Process payment: first pay royalty to creator
    (unwrap! (pay-royalty token-id price) ERR-INSUFFICIENT-FUNDS)
    
    ;; Calculate amount to seller after royalty
    (let (
      (royalty-percentage (get royalty-percentage token-data))
      (royalty-amount (/ (* price royalty-percentage) u100))
      (seller-amount (- price royalty-amount))
    )
      ;; Transfer STX to seller
      (unwrap! (stx-transfer? seller-amount tx-sender seller) ERR-INSUFFICIENT-FUNDS)
      
      ;; Update token ownership
      (map-set tokens
        { token-id: token-id }
        (merge token-data { 
          owner: tx-sender, 
          is-listed: false, 
          price: u0 
        })
      )
      
      ;; Update ownership records
      (remove-token-from-owner token-id seller)
      (add-token-to-owner token-id tx-sender)
      
      ;; Add to provenance history
      (add-provenance-entry token-id tx-sender price)
      
      (ok true)
    )
  )
)

;; Create a new collection
(define-public (create-collection (name (string-utf8 100)) (description (string-utf8 500)))
  (let (
    (collection-id (var-get next-collection-id))
    (creator tx-sender)
  )
    ;; Create the collection
    (map-set collections
      { collection-id: collection-id }
      {
        name: name,
        description: description,
        creator: creator,
        creation-date: block-height,
        token-ids: (list)
      }
    )
    
    ;; Update the collection ID counter
    (var-set next-collection-id (+ collection-id u1))
    
    (ok collection-id)
  )
)

;; Add token to collection
(define-public (add-token-to-collection (token-id uint) (collection-id uint))
  (let (
    (token-data (unwrap! (map-get? tokens { token-id: token-id }) ERR-TOKEN-NOT-FOUND))
    (collection-data (unwrap! (map-get? collections { collection-id: collection-id }) ERR-COLLECTION-NOT-FOUND))
    (current-tokens (get token-ids collection-data))
  )
    ;; Check token ownership
    (asserts! (is-eq tx-sender (get owner token-data)) ERR-NOT-AUTHORIZED)
    ;; Check collection ownership
    (asserts! (is-eq tx-sender (get creator collection-data)) ERR-NOT-AUTHORIZED)
    ;; Check if token is already in collection
    (asserts! (is-none (index-of current-tokens token-id)) ERR-TOKEN-ALREADY-IN-COLLECTION)
    ;; Check collection size limit
    (asserts! (< (len current-tokens) u100) ERR-COLLECTION-LIMIT-EXCEEDED)
    
    ;; Add token to collection
    (map-set collections
      { collection-id: collection-id }
      (merge collection-data { 
        token-ids: (append current-tokens token-id) 
      })
    )
    
    (ok true)
  )
)

;; Remove token from collection
(define-public (remove-token-from-collection (token-id uint) (collection-id uint))
  (let (
    (collection-data (unwrap! (map-get? collections { collection-id: collection-id }) ERR-COLLECTION-NOT-FOUND))
    (current-tokens (get token-ids collection-data))
  )
    ;; Check collection ownership
    (asserts! (is-eq tx-sender (get creator collection-data)) ERR-NOT-AUTHORIZED)
    ;; Check if token is in collection
    (asserts! (is-some (index-of current-tokens token-id)) ERR-TOKEN-NOT-IN-COLLECTION)
    
    ;; Remove token from collection
    (map-set collections
      { collection-id: collection-id }
      (merge collection-data { 
        token-ids: (filter remove-id-filter current-tokens)
      })
    )
    (where remove-id-filter (id) (not (is-eq id token-id)))
    
    (ok true)
  )
)

;; Update token metadata
(define-public (update-token-metadata 
  (token-id uint) 
  (title (string-utf8 100)) 
  (description (string-utf8 500))
  (audio-url (string-utf8 256))
)
  (let ((token-data (unwrap! (map-get? tokens { token-id: token-id }) ERR-TOKEN-NOT-FOUND)))
    ;; Check if sender is the creator
    (asserts! (is-eq tx-sender (get creator token-data)) ERR-NOT-AUTHORIZED)
    
    ;; Update metadata
    (map-set tokens
      { token-id: token-id }
      (merge token-data { 
        title: title, 
        description: description,
        audio-url: audio-url 
      })
    )
    
    (ok true)
  )
)