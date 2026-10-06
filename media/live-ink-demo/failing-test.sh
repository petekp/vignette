#!/bin/zsh
# The demo's terminal: a test run that fails on the invoice's tax, then a shell.
clear
print -P "%F{244}~/juniper%f %F{2}❯%f pytest tests/test_invoice.py"
sleep 0.4
print -P "%F{244}============================= test session starts ==============================%f"
print -P "collected 6 items"
print
print -P "tests/test_invoice.py %F{2}....%f%F{1}F%f%F{2}.%f                                       [100%]"
print
print -P "%F{1}___________________________ test_tax_applies_after_discount ___________________________%f"
print
print -P "    def test_tax_applies_after_discount():"
print -P "        invoice = Invoice(items=SAMPLE, discount=Decimal(\"0.10\"), tax_rate=Decimal(\"0.08\"))"
print -P "%F{1}>       assert invoice.total == Decimal(\"3975.48\")%f"
print -P "%F{1}E       AssertionError: assert Decimal('4008.20') == Decimal('3975.48')%f"
print
print -P "billing/invoice.py:42: in total"
print -P "    tax = self.subtotal * self.tax_rate"
print -P "%F{1}========================= 1 failed, 5 passed in 0.31s ==========================%f"
print
# A shell with no rc files, so its prompt names nothing of the machine's.
PS1='%F{244}~/juniper%f %F{2}❯%f ' exec zsh -f -i
