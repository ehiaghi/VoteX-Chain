;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; VoteX.clar
;; Tokenized Voting Power System (simple, readable, Clarinet-ready)
;; - Built-in fungible governance token: votex-token
;; - Proposals: create, vote (token-weighted), finalize
;; - Prevents double-voting per proposal
;; - Stores proposal metadata, votes, and status on-chain
;; Version: 1.0
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-fungible-token votex-token u1000000)

;; Contract owner (deployer)
(define-constant contract-owner tx-sender)

;; Proposal status strings
(define-constant STATUS-OPEN "OPEN")
(define-constant STATUS-FINALIZED "FINALIZED")
(define-constant STATUS-CANCELLED "CANCELLED")

;; Data vars
(define-data-var proposal-counter uint u0) ;; increments for new proposals

;; Proposal structure stored in a map keyed by proposal-id
(define-map proposals
  { id: uint }
  {
    title: (string-ascii 100),
    description: (string-ascii 500),
    creator: principal,
    deadline: uint,          ;; block-height when voting closes (inclusive)
    for-votes: uint,         ;; total weighted FOR votes
    against-votes: uint,     ;; total weighted AGAINST votes
    status: (string-ascii 20)
  }
)

;; Votes map: key (proposal-id, voter) -> { choice: bool, weight: uint }
(define-map votes
  { proposal-id: uint, voter: principal }
  { choice: bool, weight: uint } )

;; Event-like tuples (emitted via print)

;; -----------------------
;; Helper / read-only
;; -----------------------

;; Get current token balance for a principal (voting weight)
(define-read-only (voting-weight (who principal))
  (ft-get-balance votex-token who)
)

;; Get proposal by id
(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals {id: proposal-id})
)

;; Check if an address has voted on a proposal
(define-read-only (has-voted (proposal-id uint) (who principal))
  (ok (is-some (map-get? votes {proposal-id: proposal-id, voter: who})))
)

;; -----------------------
;; Admin / Token Minting
;; -----------------------

;; Mint governance tokens to an address (only contract owner)
(define-public (mint-tokens (recipient principal) (amount uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) (err u0))
    (ft-mint? votex-token amount recipient)
  )
)

;; -----------------------
;; Proposal lifecycle
;; -----------------------

;; Create a new proposal
;; duration = number of blocks the proposal will be open (must be > 0)
(define-public (create-proposal (title (string-ascii 100)) (description (string-ascii 500)) (duration uint))
  (begin
    (asserts! (> duration u0) (err "ERR_INVALID_DURATION"))
      (let (
           (new-id (+ (var-get proposal-counter) u1))
           (deadline (+ burn-block-height duration)) ;; voting closes at block <= deadline
         )
      (begin
        (map-set proposals {id: new-id}
          {
            title: title,
            description: description,
            creator: tx-sender,
            deadline: deadline,
            for-votes: u0,
            against-votes: u0,
            status: STATUS-OPEN
          })
        (var-set proposal-counter new-id)
        (print (tuple (event "proposal-created") (id new-id) (creator tx-sender) (deadline deadline) (title title)))
        (ok new-id)
      )
    )
  )
)

;; Cast a vote on a proposal (support = true for FOR, false for AGAINST)
(define-public (cast-vote (proposal-id uint) (support bool))
  (begin
    ;; ensure proposal exists
    (match (map-get? proposals {id: proposal-id})
      proposal
        (let (
            (status (get status proposal))
            (deadline (get deadline proposal))
            (current-weight (ft-get-balance votex-token tx-sender))
           )
        (begin
          ;; proposal must be open
          (asserts! (is-eq status STATUS-OPEN) (err "ERR_PROPOSAL_NOT_OPEN"))
          ;; within voting window
          (asserts! (<= burn-block-height deadline) (err "ERR_VOTING_CLOSED"))
          ;; voter must have positive token balance
          (asserts! (> current-weight u0) (err "ERR_NO_VOTING_POWER"))
          ;; ensure not already voted
          (asserts! (is-none (map-get? votes {proposal-id: proposal-id, voter: tx-sender})) (err "ERR_ALREADY_VOTED"))
          ;; record the vote
          (map-set votes {proposal-id: proposal-id, voter: tx-sender}
            { choice: support, weight: current-weight })
          ;; update aggregated tallies
          (if support
              (map-set proposals {id: proposal-id}
                {
                  title: (get title proposal),
                  description: (get description proposal),
                  creator: (get creator proposal),
                  deadline: deadline,
                  for-votes: (+ (get for-votes proposal) current-weight),
                  against-votes: (get against-votes proposal),
                  status: status
                })
              (map-set proposals {id: proposal-id}
                {
                  title: (get title proposal),
                  description: (get description proposal),
                  creator: (get creator proposal),
                  deadline: deadline,
                  for-votes: (get for-votes proposal),
                  against-votes: (+ (get against-votes proposal) current-weight),
                  status: status
                })
          )
          (print (tuple (event "vote-cast") (proposal-id proposal-id) (voter tx-sender) (choice support) (weight current-weight)))
          (ok current-weight)
        )
      )
      (err "ERR_PROPOSAL_NOT_FOUND")
    )
  )
)

;; Finalize a proposal after deadline. Anyone can call finalize.
;; It marks proposal as FINALIZED and emits an event with result ("APPROVED" or "REJECTED" or "TIE").
(define-public (finalize-proposal (proposal-id uint))
  (begin
    (match (map-get? proposals {id: proposal-id})
      proposal
      (let (
             (status (get status proposal))
             (deadline (get deadline proposal))
             (for-v (get for-votes proposal))
             (against-v (get against-votes proposal))
           )
        (begin
          (asserts! (is-eq status STATUS-OPEN) (err "ERR_ALREADY_FINALIZED_OR_CANCELLED"))
          (asserts! (> burn-block-height deadline) (err "ERR_VOTING_STILL_OPEN"))
          ;; determine result
          (let ((result
                 (if (> for-v against-v) "APPROVED"
                   (if (< for-v against-v) "REJECTED" "TIE"))))
            (map-set proposals {id: proposal-id}
              {
                title: (get title proposal),
                description: (get description proposal),
                creator: (get creator proposal),
                deadline: deadline,
                for-votes: for-v,
                against-votes: against-v,
              status: STATUS-FINALIZED
            })
            (print (tuple (event "proposal-finalized") (proposal-id proposal-id) (result result) (for-votes for-v) (against-votes against-v)))
            (ok result)
          )
        )
      )
      (err "ERR_PROPOSAL_NOT_FOUND")
    )
  )
)

;; Cancel a proposal (only creator or contract owner before finalization)
(define-public (cancel-proposal (proposal-id uint))
  (begin
    (match (map-get? proposals {id: proposal-id})
      proposal
      (let ((status (get status proposal)) (creator (get creator proposal)))
        (begin
          (asserts! (is-eq status STATUS-OPEN) (err "ERR_NOT_OPEN"))
          (asserts! (or (is-eq tx-sender creator) (is-eq tx-sender contract-owner)) (err "ERR_NOT_AUTHORIZED"))
          (map-set proposals {id: proposal-id}
            {
              title: (get title proposal),
              description: (get description proposal),
              creator: creator,
              deadline: (get deadline proposal),
              for-votes: (get for-votes proposal),
              against-votes: (get against-votes proposal),
              status: STATUS-CANCELLED
            })
          (ok "CANCELLED")
        )
      )
      (err "ERR_PROPOSAL_NOT_FOUND")
    )
  )
)

;; Read-only: list basic info for proposal (readers will get Option response)
(define-read-only (proposal-summary (proposal-id uint))
  (match (map-get? proposals {id: proposal-id})
    proposal
    (ok (tuple (id proposal-id)
               (title (get title proposal))
               (creator (get creator proposal))
               (deadline (get deadline proposal))
               (for-votes (get for-votes proposal))
               (against-votes (get against-votes proposal))
               (status (get status proposal))))
    (err "ERR_PROPOSAL_NOT_FOUND")
  )
)