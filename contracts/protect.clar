;; Financial Protection System

;; Define error constants with more specific messages
(define-constant ERR_INVALID_AMOUNT (err u100))
(define-constant ERR_INSUFFICIENT_FUNDS (err u101))
(define-constant ERR_REQUEST_NOT_FOUND (err u102))
(define-constant ERR_UNAUTHORIZED (err u103))
(define-constant ERR_ALREADY_PROTECTED (err u104))
(define-constant ERR_INVALID_PRINCIPAL (err u105))
(define-constant ERR_NOT_PROTECTED (err u106))
(define-constant ERR_ZERO_AMOUNT (err u107))
(define-constant ERR_REQUEST_ALREADY_PROCESSED (err u108))
(define-constant ERR_POOL_EMPTY (err u109))
(define-constant ERR_REQUEST_NOT_EXPIRED (err u110))
(define-constant ERR_REQUEST_EXCEEDS_PROTECTED (err u111))
(define-constant ERR_CONTRACT_PAUSED (err u112))
(define-constant ERR_FEE_CALCULATION_FAILED (err u113))

;; Define the contract
(define-data-var protection-pool uint u0)
(define-data-var contract-owner principal tx-sender)
(define-data-var contract-paused bool false)
(define-map protected-contracts principal uint)
(define-map protection-requests { requester: principal, amount: uint } { status: (string-ascii 20), timestamp: uint, paid-amount: uint })

;; Define the request expiration period (e.g., 30 days in blocks, assuming 10-minute block times)
(define-constant REQUEST_EXPIRATION_PERIOD u4320)

;; Define guard for paused contract
(define-private (contract-not-paused)
  (not (var-get contract-paused)))

;; Helper function to calculate payout amount
(define-private (calculate-payout-amount (request-amount uint) (pool-balance uint))
  (if (>= pool-balance request-amount)
      request-amount
      pool-balance))

;; Function to purchase protection
(define-public (purchase-protection (amount uint))
  (begin
    (asserts! (contract-not-paused) ERR_CONTRACT_PAUSED)
    (let ((caller tx-sender))
      (asserts! (> amount u0) ERR_ZERO_AMOUNT)
      (asserts! (is-none (map-get? protected-contracts caller)) ERR_ALREADY_PROTECTED)
      (match (stx-transfer? amount caller (as-contract tx-sender))
        success (begin
          (var-set protection-pool (+ (var-get protection-pool) amount))
          (map-set protected-contracts caller amount)
          (print { event: "protection-purchased", protected-amount: amount, buyer: caller })
          (ok true))
        error (err error)))))

;; Function to increase existing protection amount
(define-public (increase-protection (additional-amount uint))
  (begin
    (asserts! (contract-not-paused) ERR_CONTRACT_PAUSED)
    (let (
      (caller tx-sender)
      (current-protection (default-to u0 (map-get? protected-contracts caller)))
    )
      (asserts! (> additional-amount u0) ERR_ZERO_AMOUNT)
      (asserts! (is-some (map-get? protected-contracts caller)) ERR_NOT_PROTECTED)
      (match (stx-transfer? additional-amount caller (as-contract tx-sender))
        success (begin
          (var-set protection-pool (+ (var-get protection-pool) additional-amount))
          (map-set protected-contracts caller (+ current-protection additional-amount))
          (print { event: "protection-increased", additional-amount: additional-amount, new-total: (+ current-protection additional-amount), buyer: caller })
          (ok true))
        error (err error)))))

;; Function to withdraw excess protection
(define-public (reduce-protection (reduction-amount uint))
  (begin
    (asserts! (contract-not-paused) ERR_CONTRACT_PAUSED)
    (let (
      (caller tx-sender)
      (current-protection (unwrap! (map-get? protected-contracts caller) ERR_NOT_PROTECTED))
    )
      (asserts! (> reduction-amount u0) ERR_ZERO_AMOUNT)
      (asserts! (<= reduction-amount current-protection) ERR_INSUFFICIENT_FUNDS)
      ;; Check for any pending requests
      (asserts! (is-none (map-get? protection-requests { requester: caller, amount: current-protection })) ERR_REQUEST_ALREADY_PROCESSED)
      (match (as-contract (stx-transfer? reduction-amount tx-sender caller))
        success (begin
          (var-set protection-pool (- (var-get protection-pool) reduction-amount))
          (if (is-eq reduction-amount current-protection)
              (map-delete protected-contracts caller)
              (map-set protected-contracts caller (- current-protection reduction-amount)))
          (print { event: "protection-reduced", reduction-amount: reduction-amount, remaining: (- current-protection reduction-amount), owner: caller })
          (ok true))
        error (err error)))))

;; Function to file a protection request
(define-public (file-request (request-amount uint))
  (begin
    (asserts! (contract-not-paused) ERR_CONTRACT_PAUSED)
    (let (
      (caller tx-sender)
      (protected-amount (default-to u0 (map-get? protected-contracts caller)))
    )
      (asserts! (> request-amount u0) ERR_ZERO_AMOUNT)
      (asserts! (is-some (map-get? protected-contracts caller)) ERR_NOT_PROTECTED)
      (asserts! (>= protected-amount request-amount) ERR_INSUFFICIENT_FUNDS)
      (asserts! (is-none (map-get? protection-requests { requester: caller, amount: request-amount })) ERR_REQUEST_ALREADY_PROCESSED)
      (map-set protection-requests { requester: caller, amount: request-amount } { status: "pending", timestamp: block-height, paid-amount: u0 })
      (print { event: "request-filed", requester: caller, request-amount: request-amount, timestamp: block-height })
      (ok true))))

;; Function to approve and pay out a request
(define-public (approve-request (requester principal) (request-amount uint))
  (begin
    (asserts! (contract-not-paused) ERR_CONTRACT_PAUSED)
    (let (
      (request-key { requester: requester, amount: request-amount })
      (request-data (unwrap! (map-get? protection-requests request-key) ERR_REQUEST_NOT_FOUND))
      (pool-balance (var-get protection-pool))
      (protected-amount (unwrap! (map-get? protected-contracts requester) ERR_NOT_PROTECTED))
    )
      (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
      (asserts! (is-eq (get status request-data) "pending") ERR_REQUEST_ALREADY_PROCESSED)
      (asserts! (> pool-balance u0) ERR_POOL_EMPTY)
      (asserts! (<= request-amount protected-amount) ERR_REQUEST_EXCEEDS_PROTECTED)
      (asserts! (< (- block-height (get timestamp request-data)) REQUEST_EXPIRATION_PERIOD) ERR_REQUEST_NOT_EXPIRED)
      (let ((payout-amount (calculate-payout-amount request-amount pool-balance)))
        (match (as-contract (stx-transfer? payout-amount tx-sender requester))
          success (begin
            (var-set protection-pool (- pool-balance payout-amount))
            (if (< payout-amount request-amount)
                (map-set protection-requests request-key { status: "partially-paid", timestamp: block-height, paid-amount: payout-amount })
                (begin
                  (map-delete protection-requests request-key)
                  (map-delete protected-contracts requester)))
            (print { event: "request-approved", requester: requester, request-amount: request-amount, payout-amount: payout-amount })
            (ok payout-amount))
          error (err error))))))

;; Function to reject a request
(define-public (reject-request (requester principal) (request-amount uint))
  (begin
    (asserts! (contract-not-paused) ERR_CONTRACT_PAUSED)
    (let (
      (request-key { requester: requester, amount: request-amount })
      (request-data (unwrap! (map-get? protection-requests request-key) ERR_REQUEST_NOT_FOUND))
    )
      (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
      (asserts! (is-eq (get status request-data) "pending") ERR_REQUEST_ALREADY_PROCESSED)
      (asserts! (< (- block-height (get timestamp request-data)) REQUEST_EXPIRATION_PERIOD) ERR_REQUEST_NOT_EXPIRED)
      (map-set protection-requests request-key { status: "rejected", timestamp: (get timestamp request-data), paid-amount: u0 })
      (print { event: "request-rejected", requester: requester, request-amount: request-amount })
      (ok true))))

;; Function to check and expire a single request
(define-public (check-and-expire-request (requester principal) (request-amount uint))
  (let (
    (request-key { requester: requester, amount: request-amount })
    (request-data (unwrap! (map-get? protection-requests request-key) ERR_REQUEST_NOT_FOUND))
  )
    (if (and (is-eq (get status request-data) "pending")
             (>= (- block-height (get timestamp request-data)) REQUEST_EXPIRATION_PERIOD))
        (begin
          (map-set protection-requests request-key { status: "expired", timestamp: (get timestamp request-data), paid-amount: u0 })
          (print { event: "request-expired", requester: requester, request-amount: request-amount })
          (ok true))
        (ok false))))

;; Function to change the contract owner
(define-public (change-contract-owner (new-owner principal))
  (begin
    (asserts! (contract-not-paused) ERR_CONTRACT_PAUSED)
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
    (asserts! (not (is-eq new-owner 'SP000000000000000000002Q6VF78)) ERR_INVALID_PRINCIPAL)
    (print { event: "contract-owner-changed", old-owner: (var-get contract-owner), new-owner: new-owner })
    (ok (var-set contract-owner new-owner))))

;; Function to pause contract in emergency
(define-public (set-contract-pause (paused bool))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
    (ok (var-set contract-paused paused))))

;; Function to calculate protection fee based on amount and duration
(define-read-only (calculate-protection-fee (amount uint) (duration uint))
  (let (
    (base-fee-rate u1) ;; 0.1% base fee rate (1/1000)
    (duration-multiplier (/ duration u144)) ;; Normalize duration to days (assuming 144 blocks per day)
  )
    (ok (/ (* amount (* base-fee-rate duration-multiplier)) u1000))))

;; Read-only functions

;; Function to get the current protection pool balance
(define-read-only (get-pool-balance)
  (ok (var-get protection-pool)))

;; Function to check if a contract is protected
(define-read-only (is-protected (contract principal))
  (is-some (map-get? protected-contracts contract)))

;; Function to get the protected amount for a contract
(define-read-only (get-protected-amount (contract principal))
  (ok (default-to u0 (map-get? protected-contracts contract))))

;; Function to get the request status for a contract
(define-read-only (get-request-status (requester principal) (request-amount uint))
  (match (map-get? protection-requests { requester: requester, amount: request-amount })
    request-data (ok { status: (get status request-data), timestamp: (get timestamp request-data), paid-amount: (get paid-amount request-data) })
    ERR_REQUEST_NOT_FOUND))

;; Function to get all pending requests for a contract
(define-read-only (get-pending-requests (contract principal))
  (ok {
    contract: contract,
    protected-amount: (default-to u0 (map-get? protected-contracts contract)),
    has-protection: (is-some (map-get? protected-contracts contract)),
    pending-request: (map-get? protection-requests { requester: contract, amount: (default-to u0 (map-get? protected-contracts contract)) })
  }))

;; Function to get contract statistics
(define-read-only (get-contract-stats)
  (ok {
    pool-balance: (var-get protection-pool),
    is-paused: (var-get contract-paused),
    owner: (var-get contract-owner),
    expiration-period: REQUEST_EXPIRATION_PERIOD
  }))