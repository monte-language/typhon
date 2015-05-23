def chain([var fount] + drains):
    for drain in drains:
        fount := fount<-flowTo(drain)
    return fount

[=> chain]
