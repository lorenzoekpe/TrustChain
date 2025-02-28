;; TrustChain - Decentralized Identity Verification Protocol
;; A trust-based identity verification system built on Stacks

;; Constants
(define-constant contract-owner tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u1))
(define-constant ERR-INSUFFICIENT-VERIFICATION (err u2))
(define-constant ERR-INVALID-PROOF (err u3))
(define-constant ERR-LOW-TRUST-SCORE (err u4))
(define-constant MAX-TRUST-SCORE u1000)
(define-constant MIN-TRUST-SCORE u0)
(define-constant BASE-VERIFICATION-FEE u1000) ;; 10% base fee
(define-constant MAX-ACTIVE-VERIFICATIONS u3)
(define-constant VERIFICATION-DURATION u1440) ;; Expiry period in blocks

;; Data Variables
(define-data-var minimum-trust-score uint u500)
(define-data-var endorsement-threshold uint u150) ;; 150% endorsement threshold
(define-data-var next-verification-id uint u0)

;; Data Maps
(define-map identity-profiles
    principal
    {
        trust-score: uint,
        total-verified: uint,
        total-endorsed: uint,
        active-verifications: uint,
        last-activity: uint
    }
)

(define-map verifications
    uint
    {
        subject: principal,
        proof: uint,
        endorsement: uint,
        expiry-block: uint,
        status: (string-ascii 20),
        verification-fee: uint
    }
)

;; Initialize identity profile
(define-public (initialize-profile)
    (let ((sender tx-sender))
        (ok (map-set identity-profiles
            sender
            {
                trust-score: u500,
                total-verified: u0,
                total-endorsed: u0,
                active-verifications: u0,
                last-activity: u0
            }
        ))
    )
)

;; Calculate verification fee based on trust score
(define-private (calculate-verification-fee (trust-score uint))
    (let (
        (score-factor (/ (* trust-score u100) MAX-TRUST-SCORE))
        (fee-reduction (/ (* score-factor u500) u100)) ;; Up to 5% reduction
        )
        (if (>= fee-reduction BASE-VERIFICATION-FEE)
            u500 ;; Minimum 5% verification fee
            (- BASE-VERIFICATION-FEE fee-reduction))
    )
)

;; Request identity verification
(define-public (request-verification (proof uint) (endorsement uint))
    (let (
        (sender tx-sender)
        (user-data (unwrap! (map-get? identity-profiles sender) ERR-NOT-AUTHORIZED))
        )
        
        ;; Check trust score
        (asserts! (>= (get trust-score user-data) (var-get minimum-trust-score))
            ERR-LOW-TRUST-SCORE)
        
        ;; Check endorsement threshold
        (asserts! (>= (* endorsement u100) (* proof (var-get endorsement-threshold)))
            ERR-INSUFFICIENT-VERIFICATION)
        
        ;; Check active verifications limit
        (asserts! (< (get active-verifications user-data) MAX-ACTIVE-VERIFICATIONS)
            ERR-NOT-AUTHORIZED)
        
        ;; Create verification
        (create-verification sender proof endorsement)
    )
)

;; Private function to create verification
(define-private (create-verification (subject principal) (proof uint) (endorsement uint))
    (let (
        (verification-id (+ (var-get next-verification-id) u1))
        (user-data (unwrap! (map-get? identity-profiles subject) ERR-NOT-AUTHORIZED))
        (verification-fee (calculate-verification-fee (get trust-score user-data)))
        )
        (begin
            (map-set verifications
                verification-id
                {
                    subject: subject,
                    proof: proof,
                    endorsement: endorsement,
                    expiry-block: (+ burn-block-height VERIFICATION-DURATION), ;; Valid for ~10 days
                    status: "active",
                    verification-fee: verification-fee
                }
            )
            ;; Update user's active verifications count
            (map-set identity-profiles
                subject
                (merge user-data { 
                    active-verifications: (+ (get active-verifications user-data) u1),
                    total-verified: (+ (get total-verified user-data) proof)
                })
            )
            (var-set next-verification-id verification-id)
            (ok verification-id)
        )
    )
)

;; Get all active verifications for a user
(define-read-only (get-user-active-verifications (user principal))
    (let (
        (user-data (unwrap! (map-get? identity-profiles user) ERR-NOT-AUTHORIZED))
        (active-count (get active-verifications user-data))
        )
        (ok {
            active-verification-count: active-count,
            total-verified: (get total-verified user-data),
            total-endorsed: (get total-endorsed user-data)
        })
    )
)

;; Get specific verification status
(define-read-only (get-verification-status (verification-id uint))
    (match (map-get? verifications verification-id)
        verification (ok {
            status: (get status verification),
            proof: (get proof verification),
            verification-fee: (get verification-fee verification),
            expiry-block: (get expiry-block verification)
        })
        ERR-NOT-AUTHORIZED
    )
)

;; Endorse verification
(define-public (endorse-verification (verification-id uint))
    (let (
        (verification (unwrap! (map-get? verifications verification-id) ERR-NOT-AUTHORIZED))
        (sender tx-sender)
        (user-data (unwrap! (map-get? identity-profiles sender) ERR-NOT-AUTHORIZED))
        )
        
        ;; Verify sender is subject
        (asserts! (is-eq sender (get subject verification)) ERR-NOT-AUTHORIZED)
        
        ;; Update verification status and user profile
        (begin
            (map-set verifications verification-id (merge verification { status: "endorsed" }))
            (map-set identity-profiles
                sender
                (merge user-data { 
                    active-verifications: (- (get active-verifications user-data) u1),
                    total-endorsed: (+ (get total-endorsed user-data) (get proof verification))
                })
            )
            (unwrap! (update-identity-profile sender true) ERR-NOT-AUTHORIZED)
            (ok true)
        )
    )
)

;; Private function to update identity profile
(define-private (update-identity-profile (user principal) (positive bool))
    (let (
        (profile (unwrap! (map-get? identity-profiles user) ERR-NOT-AUTHORIZED))
        (current-score (get trust-score profile))
        (new-score (if positive
            (if (>= (+ current-score u10) MAX-TRUST-SCORE)
                MAX-TRUST-SCORE
                (+ current-score u10))
            (if (<= (- current-score u50) MIN-TRUST-SCORE)
                MIN-TRUST-SCORE
                (- current-score u50))))
        )
        (begin
            (map-set identity-profiles
                user
                (merge profile { trust-score: new-score })
            )
            (ok new-score)
        )
    )
)

;; Getter for identity profile
(define-read-only (get-identity-profile (user principal))
    (map-get? identity-profiles user)
)

;; Getter for verification details
(define-read-only (get-verification-details (verification-id uint))
    (map-get? verifications verification-id)
)