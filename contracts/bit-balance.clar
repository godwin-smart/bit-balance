;; Title: BitBalance - Automated Portfolio Management Protocol
;; Summary: A decentralized portfolio management system enabling users to create, manage, and automatically rebalance cryptocurrency portfolios on Stacks Layer 2
;; Description: BitBalance revolutionizes DeFi portfolio management by providing a trustless, automated solution for maintaining optimal asset allocation.
;;              Users can create diversified portfolios with up to 10 different tokens, set custom allocation percentages, and leverage automatic rebalancing
;;              mechanisms to maintain their desired investment strategy. Built on Stacks Layer 2 for Bitcoin-secured smart contracts with minimal fees
;;              and maximum security. The protocol implements sophisticated validation, user access controls, and efficient storage patterns optimized
;;              for the UTXO-based architecture of Bitcoin-backed smart contracts.

;; ERROR CODES

(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-PORTFOLIO (err u101))
(define-constant ERR-INSUFFICIENT-BALANCE (err u102))
(define-constant ERR-INVALID-TOKEN (err u103))
(define-constant ERR-REBALANCE-FAILED (err u104))
(define-constant ERR-PORTFOLIO-EXISTS (err u105))
(define-constant ERR-INVALID-PERCENTAGE (err u106))
(define-constant ERR-MAX-TOKENS-EXCEEDED (err u107))
(define-constant ERR-LENGTH-MISMATCH (err u108))
(define-constant ERR-USER-STORAGE-FAILED (err u109))
(define-constant ERR-INVALID-TOKEN-ID (err u110))

;; DATA VARIABLES & CONSTANTS

(define-data-var protocol-owner principal tx-sender)
(define-data-var portfolio-counter uint u0)
(define-data-var protocol-fee uint u25) ;; 0.25% represented as basis points

;; Protocol Constants
(define-constant MAX-TOKENS-PER-PORTFOLIO u10)
(define-constant BASIS-POINTS u10000)
(define-constant REBALANCE-THRESHOLD u144) ;; 24 hours in blocks
(define-constant MAX-USER-PORTFOLIOS u20)

;; DATA MAPS

;; Core portfolio metadata storage
(define-map Portfolios
  uint ;; portfolio-id
  {
    owner: principal,
    created-at: uint,
    last-rebalanced: uint,
    total-value: uint,
    active: bool,
    token-count: uint,
  }
)

;; Individual asset allocation within portfolios
(define-map PortfolioAssets
  {
    portfolio-id: uint,
    token-id: uint,
  }
  {
    target-percentage: uint,
    current-amount: uint,
    token-address: principal,
  }
)

;; User portfolio ownership tracking
(define-map UserPortfolios
  principal
  (list 20 uint)
)

;; READ-ONLY FUNCTIONS

;; Retrieve complete portfolio information
(define-read-only (get-portfolio (portfolio-id uint))
  (map-get? Portfolios portfolio-id)
)

;; Get specific asset details within a portfolio
(define-read-only (get-portfolio-asset
    (portfolio-id uint)
    (token-id uint)
  )
  (map-get? PortfolioAssets {
    portfolio-id: portfolio-id,
    token-id: token-id,
  })
)

;; Fetch all portfolios owned by a user
(define-read-only (get-user-portfolios (user principal))
  (default-to (list) (map-get? UserPortfolios user))
)

;; Calculate rebalancing requirements and timing
(define-read-only (calculate-rebalance-amounts (portfolio-id uint))
  (let (
      (portfolio (unwrap! (get-portfolio portfolio-id) ERR-INVALID-PORTFOLIO))
      (total-value (get total-value portfolio))
      (blocks-since-rebalance (- block-height (get last-rebalanced portfolio)))
    )
    (ok {
      portfolio-id: portfolio-id,
      total-value: total-value,
      needs-rebalance: (> blocks-since-rebalance REBALANCE-THRESHOLD),
      blocks-since-rebalance: blocks-since-rebalance,
    })
  )
)

;; Get protocol configuration
(define-read-only (get-protocol-info)
  {
    owner: (var-get protocol-owner),
    portfolio-counter: (var-get portfolio-counter),
    protocol-fee: (var-get protocol-fee),
    max-tokens: MAX-TOKENS-PER-PORTFOLIO,
    max-user-portfolios: MAX-USER-PORTFOLIOS,
  }
)

;; PRIVATE VALIDATION FUNCTIONS

;; Validate token ID within portfolio bounds
(define-private (validate-token-id
    (portfolio-id uint)
    (token-id uint)
  )
  (let ((portfolio (unwrap! (get-portfolio portfolio-id) false)))
    (and
      (< token-id MAX-TOKENS-PER-PORTFOLIO)
      (< token-id (get token-count portfolio))
      true
    )
  )
)

;; Ensure percentage is within valid range (0-10000 basis points)
(define-private (validate-percentage (percentage uint))
  (and (>= percentage u0) (<= percentage BASIS-POINTS))
)

;; Validate that all percentages in a portfolio sum correctly
(define-private (validate-portfolio-percentages (percentages (list 10 uint)))
  (let ((total-percentage (fold + percentages u0)))
    (and
      (is-eq total-percentage BASIS-POINTS)
      (fold check-percentage-validity percentages true)
    )
  )
)

;; Helper function to validate individual percentages
(define-private (check-percentage-validity
    (current-percentage uint)
    (valid bool)
  )
  (and valid (validate-percentage current-percentage))
)

;; Add portfolio to user's portfolio list
(define-private (add-to-user-portfolios
    (user principal)
    (portfolio-id uint)
  )
  (let (
      (current-portfolios (get-user-portfolios user))
      (new-portfolios (unwrap! (as-max-len? (append current-portfolios portfolio-id) u20)
        ERR-USER-STORAGE-FAILED
      ))
    )
    (map-set UserPortfolios user new-portfolios)
    (ok true)
  )
)

;; Initialize individual portfolio asset with validation
(define-private (initialize-portfolio-asset
    (index uint)
    (token principal)
    (percentage uint)
    (portfolio-id uint)
  )
  (if (and (>= percentage u0) (not (is-eq token tx-sender))) ;; Prevent self-referencing contracts
    (begin
      (map-set PortfolioAssets {
        portfolio-id: portfolio-id,
        token-id: index,
      } {
        target-percentage: percentage,
        current-amount: u0,
        token-address: token,
      })
      (ok true)
    )
    ERR-INVALID-TOKEN
  )
)

;; PUBLIC FUNCTIONS

;; Create a new diversified portfolio with specified tokens and allocations
(define-public (create-portfolio
    (initial-tokens (list 10 principal))
    (percentages (list 10 uint))
  )
  (let (
      (portfolio-id (+ (var-get portfolio-counter) u1))
      (token-count (len initial-tokens))
      (percentage-count (len percentages))
    )
    ;; Input validation
    (asserts! (<= token-count MAX-TOKENS-PER-PORTFOLIO) ERR-MAX-TOKENS-EXCEEDED)
    (asserts! (> token-count u1) ERR-INVALID-TOKEN)
    ;; Require at least 2 tokens
    (asserts! (is-eq token-count percentage-count) ERR-LENGTH-MISMATCH)
    (asserts! (validate-portfolio-percentages percentages) ERR-INVALID-PERCENTAGE)
    ;; Create portfolio record
    (map-set Portfolios portfolio-id {
      owner: tx-sender,
      created-at: block-height,
      last-rebalanced: block-height,
      total-value: u0,
      active: true,
      token-count: token-count,
    })
    ;; Initialize portfolio assets dynamically
    (try! (fold initialize-assets-fold
      (map pair-tokens-percentages initial-tokens percentages)
      (ok {
        portfolio-id: portfolio-id,
        index: u0,
      })
    ))
    ;; Update user's portfolio tracking
    (try! (add-to-user-portfolios tx-sender portfolio-id))
    ;; Increment global counter
    (var-set portfolio-counter portfolio-id)
    (ok portfolio-id)
  )
)

;; Helper functions for dynamic asset initialization
(define-private (pair-tokens-percentages
    (tokens (list 10 principal))
    (percentages (list 10 uint))
  )
  (map combine-token-percentage tokens percentages)
)

(define-private (combine-token-percentage
    (token principal)
    (percentage uint)
  )
  {
    token: token,
    percentage: percentage,
  }
)

(define-private (initialize-assets-fold
    (asset-data {
      token: principal,
      percentage: uint,
    })
    (acc (response {
      portfolio-id: uint,
      index: uint,
    } uint
    ))
  )
  (let (
      (current-acc (try! acc))
      (portfolio-id (get portfolio-id current-acc))
      (index (get index current-acc))
    )
    (try! (initialize-portfolio-asset index (get token asset-data)
      (get percentage asset-data) portfolio-id
    ))
    (ok {
      portfolio-id: portfolio-id,
      index: (+ index u1),
    })
  )
)