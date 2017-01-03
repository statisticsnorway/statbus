import React from 'react'
import { formatDateTime as parseFormat } from 'helpers/dateHelper'
import statUnitTypes from 'helpers/statUnitTypes'

const { number, shape, string } = React.PropTypes

const MainView = ({ unit }) => (
  <div>
    <h2><span>{statUnitTypes.get(unit.type)}</span> view</h2>
    {/* StatisticalUnit entity */}
    {unit.regId && <p>RegId: {unit.regId}</p>}
    {unit.regIdDate && <p>RegIdDate: {parseFormat(unit.regIdDate)}</p>}
    { typeof (unit.statId) === 'number' && <p>StatId: {unit.statId}</p>}
    {unit.statIdDate && <p>StatIdDate: {parseFormat(unit.statIdDate)}</p>}
    {typeof (unit.taxRegId) === 'number' && <p>TaxRegId: {unit.taxRegId}</p>}
    {unit.taxRegDate && <p>TaxRegDate: {parseFormat(unit.taxRegDate)}</p>}
    {typeof (unit.externalId) === 'number' && <p>ExternalId: {unit.externalId}</p>}
    {typeof (unit.externalIdType) === 'number' && <p>ExternalIdType: {unit.externalIdType}</p>}
    {unit.externalIdDate && <p>ExternalIdDate: {parseFormat(unit.externalIdDate)}</p>}
    {unit.dataSource && <p>DataSource: {unit.dataSource}</p>}
    {typeof (unit.refNo) === 'number' && <p>RefNo: {unit.refNo}</p>}
    {unit.name && <p>Name: {unit.name}</p>}
    {unit.shortName && <p>ShortName: {unit.shortName}</p>}
    {unit.address && <p>Address: `${unit.address.addressLine1} ${unit.address.addressLine2}`</p>}
    {typeof (unit.postalAddressId) === 'number' && <p>PostalAddressId: {unit.postalAddressId}</p>}
    {unit.telephoneNo && <p>TelephoneNo: {unit.telephoneNo}</p>}
    {unit.emailAddress && <p>EmailAddress: {unit.emailAddress}</p>}
    {unit.webAddress && <p>WebAddress: {unit.webAddress}</p>}
    {unit.regMainActivity && <p>RegMainActivity: {unit.regMainActivity}</p>}
    {unit.registrationDate && <p>RegistrationDate: {parseFormat(unit.registrationDate)}</p>}
    {unit.registrationReason && <p>RegistrationReason: {unit.registrationReason}</p>}
    {unit.liqDate && <p>LiqDate: {unit.liqDate}</p>}
    {unit.liqReason && <p>LiqReason: {unit.liqReason}</p>}
    {unit.suspensionStart && <p>SuspensionStart: {unit.suspensionStart}</p>}
    {unit.suspensionEnd && <p>SuspensionEnd: {unit.suspensionEnd}</p>}
    {unit.reorgTypeCode && <p>ReorgTypeCode: {unit.reorgTypeCode}</p>}
    {unit.reorgDate && <p>ReorgDate: {parseFormat(unit.reorgDate)}</p>}
    {unit.reorgReferences && <p>ReorgReferences: {unit.reorgReferences}</p>}
    {unit.actualAddress && <p>ActualAddress: `${unit.actualAddress.addressLine1} ${unit.actualAddress.addressLine2}
      ${unit.actualAddress.addressLine3} ${unit.actualAddress.addressLine4} ${unit.actualAddress.addressLine5}`</p>}
    {unit.contactPerson && <p>ContactPerson: {unit.contactPerson}</p>}
    {typeof (unit.employees) === 'number' && <p>Employees: {unit.employees}</p>}
    {typeof (unit.numOfPeople) === 'number' && <p>NumOfPeople: {unit.numOfPeople}</p>}
    {unit.employeesYear && <p>EmployeesYear: {parseFormat(unit.employeesYear)}</p>}
    {unit.employeesDate && <p>EmployeesDate: {parseFormat(unit.employeesDate)}</p>}
    {typeof (unit.turnover) === 'number' && <p>Turnover: {unit.turnover}</p>}
    {unit.turnoverYear && <p>TurnoverYear: {parseFormat(unit.turnoverYear)}</p>}
    {unit.turnoveDate && <p>TurnoveDate: {parseFormat(unit.turnoveDate)}</p>}
    {typeof (unit.status) === 'number' && <p>Status: {unit.status}</p>}
    {unit.statusDate && <p>StatusDate: {parseFormat(unit.statusDate)}</p>}
    {unit.notes && <p>Notes: {unit.notes}</p>}
    {unit.freeEconZone && <p>FreeEconZone: {unit.freeEconZone}</p>}
    {unit.foreignParticipation && <p>ForeignParticipation: {unit.foreignParticipation}</p>}
    {unit.classified && <p>Classified: {unit.classified}</p>}
    {unit.isDeleted && <p>IsDeleted: {unit.isDeleted}</p>}

    {/* EnterpriseUnit entity */}
    {unit.entGroupId && <p>EntGroupId: {unit.entGroupId}</p>}
    {unit.entGroupIdDate && <p>EntGroupIdDate: {unit.entGroupIdDate}</p>}
    {unit.commercial && <p>Commercial: {unit.commercial}</p>}
    {unit.instSectorCode && <p>InstSectorCode: {unit.instSectorCode}</p>}
    {unit.totalCapital && <p>TotalCapital: {unit.totalCapital}</p>}
    {unit.munCapitalShare && <p>MunCapitalShare: {unit.munCapitalShare}</p>}
    {unit.stateCapitalShare && <p>StateCapitalShare: {unit.stateCapitalShare}</p>}
    {unit.privCapitalShare && <p>PrivCapitalShare: {unit.privCapitalShare}</p>}
    {unit.foreignCapitalShare && <p>ForeignCapitalShare: {unit.foreignCapitalShare}</p>}
    {unit.foreignCapitalCurrency && <p>ForeignCapitalCurrency: {unit.foreignCapitalCurrency}</p>}
    {unit.actualMainActivity1 && <p>ActualMainActivity1: {unit.actualMainActivity1}</p>}
    {unit.actualMainActivity2 && <p>ActualMainActivity2: {unit.actualMainActivity2}</p>}
    {unit.actualMainActivityDate && <p>ActualMainActivityDate: {unit.actualMainActivityDate}</p>}
    {unit.entGroupRole && <p>EntGroupRole: {unit.entGroupRole}</p>}

    {/* LocalUnit entity */}
    {unit.legalUnitId && <p>LegalUnitId: {unit.legalUnitId}</p>}
    {unit.legalUnitIdDate && <p>LegalUnitIdDate: {parseFormat(unit.legalUnitIdDate)}</p>}

    {/* LegalUnit entity */}
    {unit.enterpriseRegId && <p>EnterpriseRegId: {unit.enterpriseRegId}</p>}
    {unit.entRegIdDate && <p>entRegIdDate: {parseFormat(unit.entRegIdDate)}</p>}
    {unit.founders && <p>Founders: {unit.founders}</p>}
    {unit.owner && <p>Owner: {unit.owner}</p>}
    {unit.market && <p>Market: {unit.market}</p>}
    {unit.legalForm && <p>LegalForm: {unit.legalForm}</p>}
    {unit.instSectorCode && <p>InstSectorCode: {unit.instSectorCode}</p>}
    {unit.totalCapital && <p>TotalCapital: {unit.totalCapital}</p>}
    {unit.munCapitalShare && <p>MunCapitalShare: {unit.munCapitalShare}</p>}
    {unit.stateCapitalShare && <p>StateCapitalShare: {unit.stateCapitalShare}</p>}
    {unit.privCapitalShare && <p>PrivCapitalShare: {unit.privCapitalShare}</p>}
    {unit.foreignCapitalShare && <p>ForeignCapitalShare: {unit.foreignCapitalShare}</p>}
    {unit.foreignCapitalCurrency && <p>ForeignCapitalCurrency: {unit.foreignCapitalCurrency}</p>}
    {unit.actualMainActivity1 && <p>ActualMainActivity1: {unit.actualMainActivity1}</p>}
    {unit.actualMainActivity2 && <p>ActualMainActivity2: {unit.actualMainActivity2}</p>}
    {unit.actualMainActivityDate && <p>ActualMainActivityDate: {unit.actualMainActivityDate}</p>}
  </div>
)

MainView.propTypes = {
  unit: shape({
    regId: number.isRequired,
    type: number.isRequired,
    name: string.isRequired,
    address: shape({
      addressLine1: string,
      addressLine2: string,
    }),
  }).isRequired,
}

export default MainView
