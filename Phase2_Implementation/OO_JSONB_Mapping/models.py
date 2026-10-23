"""Typed object composition for one TRE Listing aggregate.

Money is serialized as decimal text in JSON, preserving CAD cents exactly.
Normalized PostgreSQL rows remain authoritative; these objects are read models.
"""
from dataclasses import dataclass
from decimal import Decimal


@dataclass(frozen=True)
class Money:
    amount: Decimal
    currency: str = 'CAD'

    def __post_init__(self):
        if not self.amount.is_finite() or self.amount <= 0 or self.currency != 'CAD':
            raise ValueError('Money requires a positive finite CAD amount')

    def to_dict(self):
        return {'currency': self.currency, 'amount': format(self.amount, '.2f')}


@dataclass(frozen=True)
class ClientSummary:
    client_id: int
    display_name: str

    def to_dict(self):
        return {'client_id': self.client_id, 'display_name': self.display_name}


@dataclass(frozen=True)
class AgentSummary:
    agent_id: int
    display_name: str
    license_number: str

    def to_dict(self):
        return dict(self.__dict__)


@dataclass(frozen=True)
class PropertySummary:
    property_id: int
    property_ref: str
    address_text: str
    municipality: str
    property_type: str

    def to_dict(self):
        return dict(self.__dict__)


@dataclass(frozen=True)
class OfferSummary:
    offer_id: int
    status: str
    amount: Money
    submitted_at: str
    buyers: tuple[ClientSummary, ...]

    def __post_init__(self):
        if not self.buyers:
            raise ValueError('An offer read model must contain at least one buyer')

    def to_dict(self):
        return {'offer_id': self.offer_id, 'status': self.status,
                'amount': self.amount.to_dict(), 'submitted_at': self.submitted_at,
                'buyers': [b.to_dict() for b in self.buyers]}


@dataclass(frozen=True)
class Listing:
    listing_id: int
    status: str
    asking_price: Money
    listed_on: str
    closed_on: str | None
    property: PropertySummary
    agent: AgentSummary
    sellers: tuple[ClientSummary, ...]
    offers: tuple[OfferSummary, ...]
    schema_version: int = 1

    def __post_init__(self):
        if self.listing_id <= 0 or self.schema_version != 1:
            raise ValueError('Invalid listing identity/schema version')
        if self.status != 'DRAFT' and not self.sellers:
            raise ValueError('A non-draft listing read model requires a seller')

    def to_dict(self):
        return {'schema_version': self.schema_version, 'listing_id': self.listing_id,
                'status': self.status, 'asking_price': self.asking_price.to_dict(),
                'listed_on': self.listed_on, 'closed_on': self.closed_on,
                'property': self.property.to_dict(), 'agent': self.agent.to_dict(),
                'sellers': [s.to_dict() for s in self.sellers],
                'offers': [o.to_dict() for o in self.offers]}

    @classmethod
    def from_dict(cls, d):
        def money(m):
            return Money(Decimal(m['amount']), m['currency'])
        return cls(listing_id=d['listing_id'], status=d['status'],
                   asking_price=money(d['asking_price']), listed_on=d['listed_on'],
                   closed_on=d['closed_on'], property=PropertySummary(**d['property']),
                   agent=AgentSummary(**d['agent']),
                   sellers=tuple(ClientSummary(**s) for s in d['sellers']),
                   offers=tuple(OfferSummary(o['offer_id'],o['status'],money(o['amount']),
                                o['submitted_at'],tuple(ClientSummary(**b) for b in o['buyers']))
                                for o in d['offers']), schema_version=d['schema_version'])
