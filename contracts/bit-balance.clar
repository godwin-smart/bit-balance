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