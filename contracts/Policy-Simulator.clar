;; data vars
(define-data-var proposal-counter uint u0);; title: Policy-Simulator DAO
;; version: 1.0.0
;; summary: Test governance models with simulated outcomes before adoption
;; description: A simple DAO contract for simulating policy proposals and voting outcomes

;; constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u101))
(define-constant ERR-ALREADY-VOTED (err u102))
(define-constant ERR-VOTING-ENDED (err u103))
(define-constant ERR-SIMULATION-FAILED (err u104))
(define-constant ERR-INVALID-VOTING-PERIOD (err u105))

;; Add a maximum voting period constant for safety
(define-constant MAX-VOTING-PERIOD u1440) ;; ~10 days
(define-constant MIN-VOTING-PERIOD u1)

;; Add a helper function that explicitly validates safe arithmetic
(define-private (is-voting-active (start-block uint) (voting-period uint) (current-block uint))
  (let
    ((blocks-elapsed (if (>= current-block start-block) 
                        (- current-block start-block) 
                        u0)))
    (< blocks-elapsed voting-period)
  )
)

(define-private (is-voting-ended (start-block uint) (voting-period uint) (current-block uint))
  (let
    ((blocks-elapsed (if (>= current-block start-block) 
                        (- current-block start-block) 
                        u0)))
    (>= blocks-elapsed voting-period)
  )
)

;; data maps
(define-map proposals
  uint
  {
    title: (string-ascii 100),
    description: (string-ascii 500),
    proposer: principal,
    votes-for: uint,
    votes-against: uint,
    start-block: uint,
    voting-period: uint,
    executed: bool,
    simulation-result: (optional (string-ascii 200))
  }
)

(define-map votes
  { proposal-id: uint, voter: principal }
  { vote: bool, voting-power: uint }
)

(define-map member-voting-power principal uint)

;; public functions

(define-public (add-member (member principal) (voting-power uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    ;; Validate member is not the contract itself
    (asserts! (not (is-eq member (as-contract tx-sender))) ERR-NOT-AUTHORIZED)
    (ok (map-set member-voting-power member voting-power))
  )
)

(define-public (create-proposal (title (string-ascii 100)) (description (string-ascii 500)) (voting-period uint))
  (let
    (
      (proposal-id (+ (var-get proposal-counter) u1))
    )
    ;; Validate voting-period is within reasonable bounds
    (asserts! (and (>= voting-period MIN-VOTING-PERIOD) 
                   (<= voting-period MAX-VOTING-PERIOD)) ERR-INVALID-VOTING-PERIOD)

    (map-set proposals proposal-id
      {
        title: title,
        description: description,
        proposer: tx-sender,
        votes-for: u0,
        votes-against: u0,
        start-block: block-height,
        voting-period: voting-period,
        executed: false,
        simulation-result: none
      }
    )
    (var-set proposal-counter proposal-id)
    (ok proposal-id)
  )
)

(define-public (vote (proposal-id uint) (vote-for bool))
  (let
    (
      (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
      (voter-power (default-to u1 (map-get? member-voting-power tx-sender)))
    )
    (asserts! (is-voting-active (get start-block proposal) (get voting-period proposal) block-height) ERR-VOTING-ENDED)
    (asserts! (is-none (map-get? votes { proposal-id: proposal-id, voter: tx-sender })) ERR-ALREADY-VOTED)

    (map-set votes { proposal-id: proposal-id, voter: tx-sender } { vote: vote-for, voting-power: voter-power })

    (if vote-for
      (map-set proposals proposal-id
        (merge proposal { votes-for: (+ (get votes-for proposal) voter-power) }))
      (map-set proposals proposal-id
        (merge proposal { votes-against: (+ (get votes-against proposal) voter-power) }))
    )
    (ok true)
  )
)

(define-public (simulate-outcome (proposal-id uint) (simulation-description (string-ascii 200)))
  (let
    (
      (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
    )
    (asserts! (is-voting-ended (get start-block proposal) (get voting-period proposal) block-height) ERR-VOTING-ENDED)
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

    (map-set proposals proposal-id
      (merge proposal { simulation-result: (some simulation-description) }))
    (ok true)
  )
)

(define-public (execute-proposal (proposal-id uint))
  (let
    (
      (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
    )
    (asserts! (is-voting-ended (get start-block proposal) (get voting-period proposal) block-height) ERR-VOTING-ENDED)
    (asserts! (> (get votes-for proposal) (get votes-against proposal)) ERR-SIMULATION-FAILED)
    (asserts! (not (get executed proposal)) ERR-SIMULATION-FAILED)

    (map-set proposals proposal-id
      (merge proposal { executed: true }))
    (ok true)
  )
)

;; read only functions

(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals proposal-id)
)

(define-read-only (get-vote (proposal-id uint) (voter principal))
  (map-get? votes { proposal-id: proposal-id, voter: voter })
)

(define-read-only (get-member-power (member principal))
  (default-to u0 (map-get? member-voting-power member))
)

(define-read-only (get-proposal-count)
  (var-get proposal-counter)
)

(define-read-only (get-proposal-status (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal
    (let
      (
        (votes-for (get votes-for proposal))
        (votes-against (get votes-against proposal))
        (is-active (is-voting-active (get start-block proposal) (get voting-period proposal) block-height))
      )
      (ok {
        is-active: is-active,
        votes-for: votes-for,
        votes-against: votes-against,
        leading: (if (> votes-for votes-against) "for" "against"),
        executed: (get executed proposal),
        has-simulation: (is-some (get simulation-result proposal))
      })
    )
    ERR-PROPOSAL-NOT-FOUND
  )
)