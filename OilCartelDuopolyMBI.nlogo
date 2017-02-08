extensions [ custom-logging ]

globals [
  monopoly-quantity        ;; the amount that would be supplied by the cartel if it behaved as a monopoly
  monopoly-price           ;; the price expected if monopoly-quantity is supplied
  monopoly-profit          ;; the maximum profit that the cartel could get if it behaved as a monopolist
  total-supply             ;; sum of the actual quantity supplied by all sellers
  perfect-market-quantity  ;; the amount that would be supplied under perfect competition
  perfect-market-price     ;; the price expected under perfect competition
  individual-quota         ;; the quota for each individual seller based on the cartel agreement
  marginal-cost            ;; the cost of producing one more unit of oil
  avg-price                ;; the average price of oil across all transactions
  min-price                ;; the minimum price available for oil on the market
  low-sellers              ;; the agentset of sellers selling oil for min-price
  color-list-1             ;; used to distribute colors for display of sellers
  color-list-2             ;; used to distribute colors display of sellers
  shape-1?                 ;; used to toggle between shapes for display of sellers
  age-of-news              ;; age of news item sent to sellers.   used to clear old news
  time-period              ;; tracks current time period
]

breed [ sellers seller ]         ;; every hubnet client is a seller
breed [ buyers buyer ]

sellers-own [
                                  ;; unique user-id, input by the client when they log in
  last-sale-profit                ;; how much money the user made last time oil was sold at market
  price-1                         ;; the price of the primary, public offer
  price-2                         ;; the price of the side, private offer
  p1-quantity-offered             ;; amount of oil offered per time period at price-1
  p2-quantity-offered             ;; amount of oil offered per time period at price-2
  p1-quantity-available           ;; amount of oil at price-1 available within a time period as buyers start buying
  p2-quantity-available           ;; amount of oil at price-2 available within a time period as buyers start buying
  p1-quantity-sold                ;; amount of oil actually sold at the end of the time period at price-1
  p2-quantity-sold                ;; amount of oil actually sold at the end of the time period at price-2
  prev-p2-quantity-sold           ;; amount of oil sold at price-2 during the previous time period
  profit-needed                   ;; profit needed by each cartel member. varies by seller
  strategy                        ;; set by client.  explained in "Make Offer" procedure
  extra-output                    ;; set by client.  part of "Quota-Plus" strategy. explained in "Make Offer" procedure
  reduced-output                  ;; set by client.  part of "Quota-Minus" strategy. explained in "Make Offer" procedure
]

buyers-own [
  quantity-demanded               ;; amount demanded by a buyer at any given moment in a time period
  quantity-bought                 ;; amount bought by a buyer at any given moment in a time period
  seller-bought-from              ;; the seller who sold to the buyer last
  max-price                       ;; the maximum amount a buyer is willing to pay for their ideal quantity
  already-chosen?                 ;; only used to distribute different levels of max-price across buyers
]

to startup
  custom-logging:log-message (word "User name: " (user-input "Please enter your name"))
end

to setup
  ca
  create-buyers num-buyers [
    setxy random-pxcor random-pycor
    set color green
  ]
  initialize-shapes
  set marginal-cost 500         ;; SET MARGINAL COST*******************************
  create-new-sellers
  update-cartel-agreement
  init-globals
  init-buyer-vars
  find-lowest-offer
  compute-market-data
  set seller-strategies "Agreement"
  set-current-plot "Oil Sold on Market"
  clear-plot
  set-current-plot "Average Price of Oil"
  clear-plot
  set-current-plot "Individual Current Profit"
  clear-plot
  init-plot-current-profit
  set-current-plot "Market Share"
  clear-plot
  setup-market-share-plot
  set-current-plot "Quantity Sold at Official Price"
  init-current-quantity-plot
  set-current-plot "Quantity Sold at Lower Price"
  init-current-quantity-plot
  reset-ticks
end

to init-current-quantity-plot
  clear-plot
  ask sellers [
    create-temporary-plot-pen word "Seller " who
    set-plot-pen-color [color] of self
    ]
end

to plot-current-p1-quantity
  set-current-plot "Quantity Sold at Official Price"
  ask sellers [
    set-current-plot-pen word "Seller " who
    plot p1-quantity-sold
    ]
end

to plot-current-p2-quantity
  set-current-plot "Quantity Sold at Lower Price"
  ask sellers [
    set-current-plot-pen word "Seller " who
    plot p2-quantity-sold
    ]
end

to setup-market-share-plot
    ask sellers [
      set-current-plot "Market Share"
      create-temporary-plot-pen word "Seller" who
      set-plot-pen-color [color] of self
    ]
end

to init-globals
  set age-of-news 0
  set avg-price 0
  set min-price 0
  set monopoly-profit ( monopoly-quantity * ( monopoly-price - marginal-cost) )
  set time-period 0
end

to initialize-shapes
  ;; set up colors for seller shapes
  set color-list-1      (list  ["Red" (red)]  ["Pink" pink] ["Lime" lime] ["Sky Blue" sky] ["Magenta" magenta]
                              ["Cyan" cyan] ["Turquoise" turquoise]  ["Brown" brown] ["Blue" blue])
  set color-list-2 reverse color-list-1
  set shape-1? true
end

to go
  make-offers
  ;; ask buyers to identify seller(s) with the lowest price
  find-lowest-offer
  ;; ask buyers to purchase oil from sellers
  execute-transactions
  ;; calculate market conditions based on buyers and sellers most recent actions
  compute-market-data
  ;; ask sellers to update individual seller profit information
  update-sellers
  ;; ask buyers to update individual buyers demand satisfaction information
  update-buyers

  plot-oil-amounts
  plot-oil-price
  plot-current-profit
  plot-market-share
  plot-current-p1-quantity
  plot-current-p2-quantity
  plot-total-profit
  plot-will-to-pay

  set time-period time-period + 1

  tick
end

to update-strategy
  ifelse num-sellers-using-strategy <= count sellers[
    ask n-of num-sellers-using-strategy sellers[
      set strategy seller-strategies
    ]
  ][
  set num-sellers-using-strategy count sellers
  ]

  update-cartel-agreement
end

to make-offers
  ask sellers [
    ;; save off needed info from previous offer before creating a new one
    let prev-quantity-offered (p1-quantity-offered + p2-quantity-offered)
    ;; "Agreement" Strategy:  Produce and price exactly in accordance with
    ;; the cartel agreement
    ifelse strategy = "Agreement"
    [ set price-1 monopoly-price
      set p1-quantity-offered individual-quota
      set price-2 monopoly-price
      set p2-quantity-offered 0
     ]
    ;; "Quota-Plus" Strategy: Consistently produce "extra-output" amt beyond the quota and
    ;; offer it to the mkt for a price a little lower than the official agreement price
    [ ifelse strategy = "Quota-Plus"
      [ set price-1 monopoly-price
        set p1-quantity-offered individual-quota
        set price-2 (monopoly-price - 500)
        set p2-quantity-offered quota-plus-amount
       ]

      ;; "Quota-Minus" Strategy:  Consistently produce "reduced-output" amt below the quota
      ;; in an effort to keep prices up
      [ ifelse strategy = "Quota-Minus"
        [ set price-1 monopoly-price
          set p1-quantity-offered (individual-quota - reduced-output)
          set price-2 monopoly-price
          set p2-quantity-offered 0
        ]

        ;; "Flood Market" Strategy:  Saturate the market with low cost oil to punish cheaters.
        [ ifelse strategy = "Flood Market"
          [  set price-1 monopoly-price
             set p1-quantity-offered 0
             set price-2 marginal-cost
             set p2-quantity-offered perfect-market-quantity
;             send-news-item word user-id " unleashes reserves as warning"
          ]

          ;; "Price > MC" Strategy: Keep producing and offering additional output as long
          ;; as the price you have to offer to sell that unit is still higher than the cost
          ;; to produce it.
          [ set price-1 monopoly-price
            set p1-quantity-offered 0
            if time-period = 0 [
              set p2-quantity-offered individual-quota
              set price-2 monopoly-price
              set prev-quantity-offered p2-quantity-offered
            ]

            ;; if you didn't sell more this time than last time, undercut your own price
            ;; and try the same amount again.
            ifelse (p2-quantity-sold <= prev-p2-quantity-sold)
            [ ifelse (price-2 - 10) > marginal-cost
               [ set price-2 (price-2 - 10) ]
               [ set price-2 marginal-cost ]  ;; but don't go as far as pricing below cost
              set p2-quantity-offered prev-quantity-offered
            ]
            ;;if you did sell more that last time, increase production even a little more
            ;; (as long as price > mc)
            [ if price-2  > marginal-cost [
                set p2-quantity-offered (p2-quantity-offered + 10)  ;; amt offered keeps increasing
               ]
            ]

          ]
       ]
    ]
   ]

   ;; initialize amounts available for sale in the next time period to
   ;; the total amount you are willing to offer
   set p1-quantity-available p1-quantity-offered
   set p2-quantity-available p2-quantity-offered

  ]
end

to compute-market-data
  ;; Check the number of sellers
  ;; The actual amount supplied
  set total-supply (sum [p1-quantity-sold] of sellers + sum [p2-quantity-sold] of sellers)
  ;; Calculate the average selling price
  ifelse total-supply != 0
    [ set avg-price ( (sum [price-1 * p1-quantity-sold] of sellers with [p1-quantity-sold > 0] +
                       sum [price-2 * p2-quantity-sold] of sellers with [p2-quantity-sold > 0])
                       / total-supply )
    ]
    [ set avg-price 0 ]

  ;; Calculate hypothetical quantity and price under perfect competition
  ;; Economic theory predicts that point is where price equals marginal cost
  set perfect-market-price marginal-cost
  set perfect-market-quantity filter-zero-or-greater (num-buyers * ideal-quantity - perfect-market-price)
end


to update-sellers
  ask sellers [
    ;; figure out how much, if any, extra production there was
    let unused-p1-qty (p1-quantity-offered - p1-quantity-sold) ;; amount produced but not sold at price 1
    let extra-produced filter-zero-or-greater (p2-quantity-offered - unused-p1-qty)
    ;; update profit info
    set last-sale-profit int ( (p1-quantity-sold * price-1) + (p2-quantity-sold * price-2)
                           - ((p1-quantity-offered + extra-produced) * marginal-cost) )
    set label strategy
   ]
end

to update-buyers
  ask buyers [
    ;; update color
    ifelse quantity-bought > 0
      [ set color green ]
      [ ifelse perfect-market-price <= max-price
        [ set color yellow ]
        [ set color red ]
      ]
  ]
end


to create-new-sellers

  create-sellers 2
  [
    let max-jumps 10000
    let color-name ""
    let shape-name ""
;    set user-id id     ;; remember which client this is
    ifelse shape-1?
      [ set shape "plant1"
        set color item 1 item 0 color-list-1
        set color-name item 0 item 0 color-list-1
        set shape-name "Circle"
        set color-list-1 but-first color-list-1
      ]
      [ set shape "plant2"
        set color item 1 item 0 color-list-2
        set color-name item 0 item 0 color-list-2
        set shape-name "Square"
        set color-list-2 but-first color-list-2
      ]

    set shape-1? not shape-1?
    set size 3

    ;; locate seller
    setxy random-xcor random-ycor
    while [ any? sellers in-radius 3 and max-jumps > 0 ]
          [ rt random 360
            jump random 100
            set max-jumps (max-jumps - 1) ]


    set heading 0

    set price-1 monopoly-price
    set price-2 price-1
    set p1-quantity-offered monopoly-quantity
    set p1-quantity-available p1-quantity-offered
    set p2-quantity-available p2-quantity-offered
    set prev-p2-quantity-sold 0
    set profit-needed (monopoly-profit / count sellers)
    set strategy "Agreement"
    set label strategy
  ]
end

to init-buyer-vars
  ask buyers [
    set quantity-demanded ideal-quantity
    set quantity-bought 0
    set already-chosen? false
  ]

  ;; Vary the maximum amount a buyer is willing to pay for oil across buyers
  ;; ( Note:  The distribution below results in a aggregate relationship between
  ;; price and quantity that is linear and has a negative slope.  This simple aggregate
  ;; relationship comes in handy when calculating the cartel agreement and the perfect
  ;; competition amounts. )
  let i 0
  let buyers-remaining buyers with [ not already-chosen? ]
  while [ any? buyers-remaining ] [
    ask one-of buyers-remaining [
      set max-price (ideal-quantity * i)
      set already-chosen? true
    ]
    set i (i + 1)
    set buyers-remaining buyers with [ not already-chosen? ]
   ]
end

to find-lowest-offer
  let sellers-p2-avail (sellers with [p2-quantity-available > 0])

  ifelse any? sellers-p2-avail
   [ set min-price min ([price-2] of sellers-p2-avail)  ]
   [ set min-price monopoly-price ]

  ;; identify the seller(s) offering the lowest price
  set low-sellers sellers with [ (price-1 = min-price and p1-quantity-available > 0) or
                                 (price-2 = min-price and p2-quantity-available > 0) ]

end

to execute-transactions

   ;; before executing transactions, ask sellers to record how much they sold last time
    ;; and to initialize their quantities this time period
    ask sellers [
      set prev-p2-quantity-sold p2-quantity-sold
      set p1-quantity-sold 0
      set p2-quantity-sold 0
    ]

    ask buyers [
    set quantity-bought 0  ;; initialize quantity-bought this time period

    ifelse min-price <= max-price
      [ set quantity-demanded ideal-quantity ]
      [ set quantity-demanded 0 ]

    ;; try to buy amount you demand from sellers
    buy-from-sellers

    ;; if you bought oil this round, move close to your seller
    ifelse quantity-bought > 0
    [ setxy ([one-of (list (xcor + random-float 1.5) (xcor - random-float 1.5))]
          of seller-bought-from)
      ([one-of (list (ycor + random-float 1.5) (ycor - random-float 1.5))]
          of seller-bought-from)
    ]
      [ setxy random-pxcor random-pycor ]
   ]
end

to buy-from-sellers
     let amt-just-sold 0
     let lucky-one one-of low-sellers ;; if more than one seller offers lowest price, pick one randomly
     let avail-from-seller 0

     ;; figure out the capacity available from the low seller at the min price
     ;; but need to check to see if official price or the side price is lower first
      ifelse [price-1] of lucky-one = min-price
        [ set avail-from-seller [p1-quantity-available] of lucky-one ]
        [ ifelse [price-2] of lucky-one = min-price
          [ set avail-from-seller [p2-quantity-available] of lucky-one ]
          [ set avail-from-seller 0 ]
        ]

     ;; if the current low seller has enough capacity, buy all you need
     ;; otherwise, buy what you can from him
     ifelse avail-from-seller >= quantity-demanded
       [ set quantity-bought (quantity-bought + quantity-demanded) ]
       [ set quantity-bought (quantity-bought + avail-from-seller) ]

     ;; update info of seller you just bought from
     set amt-just-sold quantity-bought
     ask lucky-one [
      ifelse [price-1] of lucky-one = min-price
         [ set p1-quantity-available (p1-quantity-available - amt-just-sold)  ;; decrement seller's remaining amt available at p1
           set p1-quantity-sold (p1-quantity-sold + amt-just-sold)   ;; increment seller's amt purchased by buyers at p1
         ]
         [ if [price-2] of lucky-one = min-price
           [ set p2-quantity-available (p2-quantity-available - amt-just-sold)  ;; decrement seller's remaining amt available at p2
             set p2-quantity-sold (p2-quantity-sold + amt-just-sold)   ;; increment seller's purchased by buyers at p2
           ]
         ]
     ]

   ;; update your own info
   set quantity-demanded (quantity-demanded - quantity-bought)
   set seller-bought-from lucky-one

   ;; if your demand is still not satisfied, try the next seller (if any)
   if quantity-demanded > 0
   [ ifelse any? sellers with [p1-quantity-available > 0 or p2-quantity-available > 0]
         [ find-lowest-offer                   ;; of the sellers with capacity, find the lowest priced ones
           buy-from-sellers                    ;; try to buy from them
         ]
         [stop]  ;; you've tried all the sellers
   ]

end


to update-cartel-agreement

  ;; Find profit-maximizing quantity assuming cartel behaves as a unitary monopolist.
  ;; Economic theory prescribes that to maximize profits a firm should produce up to the point where
  ;; Marginal Revenue (1st derivative of demand a firm faces) equals Marginal Cost (1st derivative of total cost).
  ;; The eqn below comes from setting MR = MC and solving for monopoly-quantity.
  set monopoly-quantity filter-zero-or-greater (num-buyers * ideal-quantity - marginal-cost) / 2

  if monopoly-quantity = 0 [ output-print "Increase demand so that the cartel can start to produce" stop]
  set monopoly-price filter-zero-or-greater (num-buyers * ideal-quantity - monopoly-quantity)
  if count sellers != 0 [ set individual-quota int (monopoly-quantity / count sellers) ]
end

to-report filter-zero-or-greater [ value ]
  ifelse (value >= 0)
    [ report value ]
    [ report 0 ]
end

to-report max-of-max-price
  report [max-price] of max-one-of buyers [max-price]
end

to-report hhi
  let hhi-list []
  ask sellers [set hhi-list fput ((count buyers with [seller-bought-from = myself]) / (count buyers with [seller-bought-from != nobody]) * 100) hhi-list]
  report precision (sum map [? * ?] hhi-list) 0
end

to plot-oil-amounts
  set-current-plot "Oil Sold On Market"

  set-current-plot-pen "Agreement"
  plot monopoly-quantity

  set-current-plot-pen "Competitive"
  plot perfect-market-quantity

  set-current-plot-pen "Actual"
  plot total-supply
end

to plot-oil-price
  set-current-plot "Average Price of Oil"

  set-current-plot-pen "Average"
  plot avg-price

  set-current-plot-pen "MC"
  plot marginal-cost

  set-current-plot-pen "Agreement"
  plot monopoly-price

end

to init-plot-current-profit
    ask sellers [
      set-current-plot "Individual Current Profit"
      create-temporary-plot-pen word "Seller" who
      set-plot-pen-color [color] of self
    ]
end

to plot-current-profit
  ask sellers [
    set-current-plot "Individual Current Profit"
    set-current-plot-pen word "Seller" who
    plot last-sale-profit
    ]
end

to plot-market-share

  ask sellers [
    set-current-plot "Market Share"
    set-current-plot-pen word "Seller" who
    plot (count buyers with [seller-bought-from = myself]) / (count buyers with [seller-bought-from != nobody]) * 100
    ]
end

to plot-total-profit
  set-current-plot "Total Profit"
  plot sum [last-sale-profit] of sellers
end


to plot-will-to-pay
  set-current-plot "Max Price Buyers Willing To Pay"
  clear-plot
  ask buyers [create-temporary-plot-pen word "Buyer " who
    ]
  let tempset sort-by [[max-price] of ?1 < [max-price] of ?2] buyers
   foreach reverse tempset [
     ask ? [
       set-plot-pen-color [color] of self
       plot max-price
     ]
   ]
end
@#$#@#$#@
GRAPHICS-WINDOW
242
10
681
470
16
16
13.0
1
10
1
1
1
0
1
1
1
-16
16
-16
16
0
0
1
ticks
30.0

SLIDER
5
79
233
112
num-buyers
num-buyers
10
100
100
10
1
NIL
HORIZONTAL

SLIDER
5
112
233
145
ideal-quantity
ideal-quantity
0
100
100
10
1
NIL
HORIZONTAL

BUTTON
7
10
99
43
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
103
10
235
43
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
581
509
670
554
Official Price
monopoly-price
17
1
11

MONITOR
458
509
572
554
Target Total Barrels
monopoly-quantity
17
1
11

PLOT
683
32
1000
241
Oil Sold on Market
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"Actual" 1.0 0 -8630108 true "" ""
"Competitive" 1.0 0 -16777216 true "" ""
"Agreement" 1.0 0 -955883 true "" ""

PLOT
683
243
1000
445
Average Price of Oil
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"Average" 1.0 0 -8630108 true "" ""
"MC" 1.0 0 -16777216 true "" ""
"Agreement" 1.0 0 -955883 true "" ""

PLOT
194
475
437
644
Individual Current Profit
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS

PLOT
684
450
1001
619
Market Share
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS

CHOOSER
5
474
188
519
seller-strategies
seller-strategies
"Agreement" "Price >= MC" "Quota-Plus"
2

SLIDER
5
523
188
556
num-sellers-using-strategy
num-sellers-using-strategy
1
2
2
1
1
NIL
HORIZONTAL

BUTTON
5
602
188
642
NIL
update-strategy
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
5
563
188
596
quota-plus-amount
quota-plus-amount
0
2000
2000
1
1
NIL
HORIZONTAL

PLOT
6
319
234
469
Max Price Buyers Willing To Pay
Buyer No.
Price
0.0
10.0
0.0
10.0
true
false
"" ""
PENS

MONITOR
6
183
234
228
Num of Buyers Who Bought
count buyers with [color = green]
17
1
11

MONITOR
6
272
234
317
Num of Buyers Who Would Have Bought
count buyers with [color = yellow]
17
1
11

MONITOR
6
227
234
272
Num of Buyers Who Can't Afford
count buyers with [color = red]
17
1
11

PLOT
1007
206
1245
376
Quantity Sold at Official Price
NIL
NIL
0.0
200.0
0.0
10.0
true
false
"" ""
PENS

PLOT
1007
378
1245
541
Quantity Sold at Lower Price
NIL
NIL
0.0
200.0
0.0
10.0
true
false
"" ""
PENS

PLOT
1007
33
1243
202
Total Profit
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"total-profit-pen" 1.0 0 -7500403 true "" ""

MONITOR
526
559
627
604
Individual Quota
individual-quota
17
1
11

MONITOR
1008
596
1246
641
Herfindahl-Hirschman Index
hhi
17
1
11

MONITOR
1007
545
1121
590
Marginal Cost
marginal-cost
17
1
11

MONITOR
1125
545
1245
590
Min Price Availble
min-price
17
1
11

TEXTBOX
512
479
662
497
Agreement Info
14
0.0
1

TEXTBOX
51
55
201
73
Set Market Demand
14
0.0
1

TEXTBOX
76
154
164
172
Buyer's Info
14
0.0
1

TEXTBOX
800
10
950
28
Market Info
14
0.0
1

TEXTBOX
1061
10
1211
28
Duopoly Performance
14
0.0
1

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

plant1
true
15
Circle -1 true true 2 2 295
Rectangle -7500403 true false 90 135 120 240
Rectangle -7500403 true false 120 75 135 240
Rectangle -7500403 true false 135 105 180 240
Rectangle -7500403 true false 195 120 225 240
Rectangle -7500403 true false 180 45 195 240
Polygon -2674135 true false 105 60 120 75 135 75 105 60
Polygon -2674135 true false 165 30 180 45 195 45 165 30

plant2
true
15
Rectangle -1 true true 15 15 285 285
Rectangle -7500403 true false 90 135 120 240
Rectangle -7500403 true false 120 75 135 240
Rectangle -7500403 true false 135 105 180 240
Rectangle -7500403 true false 195 120 225 240
Rectangle -7500403 true false 180 45 195 240
Polygon -2674135 true false 105 60 120 75 135 75 105 60
Polygon -2674135 true false 165 30 180 45 195 45 165 30

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270

@#$#@#$#@
NetLogo 5.0.5-RC1
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180

@#$#@#$#@
0
@#$#@#$#@
