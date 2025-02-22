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

