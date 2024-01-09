const LookupBase = {
  Name: 'Name',
}

const StatId = {
  Name: 'StatId',
}

const CodeLookupBase = {
  Code: 'Code',
  ...LookupBase,
}

const Activity = {
  ActivityCategory: [
    'ActivityCategory',
    {
      ...CodeLookupBase,
    },
  ],
  ActivityYear: 'ActivityYear',
  Employees: 'Employees',
  Turnover: 'Turnover',
  ActivityType: 'ActivityType',
}

const Activities = {
  Activity: [
    'Activity',
    {
      ...Activity,
    },
  ],
}

const Address = {
  AddressPart1: 'AddressPart1',
  AddressPart2: 'AddressPart2',
  AddressPart3: 'AddressPart3',
  Region: [
    'Region',
    {
      ...CodeLookupBase,
    },
  ],
}

const Person = {
  GivenName: 'GivenName',
  MiddleName: 'MiddleName',
  Surname: 'Surname',
  PersonalId: 'PersonalId',
  BirthDate: 'BirthDate',
  NationalityCode: ['NationalityCode', CodeLookupBase],
  Role: 'Role',
  Sex: 'Sex',
  PhoneNumber: 'PhoneNumber',
}

const Persons = {
  Person: [
    'Person',
    {
      ...Person,
    },
  ],
}

const ForeignParticipationCountry = {
  ...LookupBase,
  Code: 'Code',
}

const ForeignParticipationCountriesUnits = {
  ForeignParticipationCountry: [
    'ForeignParticipationCountry',
    {
      ...ForeignParticipationCountry,
    },
  ],
}

const ForeignParticipation = {
  ...LookupBase,
  Code: 'Code',
}

function pathsOf(shape, prefix) {
  return Object.entries(shape)
    .map(v => v[1])
    .reduce(
      (acc, value) =>
        typeof value === 'string'
          ? [...acc, [prefix, value]]
          : [...acc, ...pathsOf(value[1], value[0]).map(path => [prefix, ...path])],
      [],
    )
}

function pathToMetaEntry(path) {
  const joined = path.join('.')
  return {
    name: joined,
    localizeKey: joined,
  }
}

function transform(shape, prefix, cur) {
  return pathsOf(shape, prefix).map(path => ({ ...(cur || {}), ...pathToMetaEntry(path) }))
}

function addFlattened(arr) {
  return arr.reduce((acc, cur) => {
    switch (cur.name) {
      case 'Activities':
        return [...acc, ...transform(Activities, 'Activities', cur)]
      case 'Address':
        return [...acc, ...transform(Address, 'Address', cur)]
      case 'ActualAddress':
        return [...acc, ...transform(Address, 'ActualAddress', cur)]
      case 'PostalAddress':
        return [...acc, ...transform(Address, 'PostalAddress', cur)]
      case 'ForeignParticipationCountriesUnits':
        return [
          ...acc,
          ...transform(
            ForeignParticipationCountriesUnits,
            'ForeignParticipationCountriesUnits',
            cur,
          ),
        ]
      case 'InstSectorCodeId':
        return [...acc, ...transform(CodeLookupBase, 'InstSectorCode', cur)]
      case 'LegalFormId':
        return [...acc, ...transform(CodeLookupBase, 'LegalForm', cur)]
      case 'Persons':
        return [...acc, ...transform(Persons, 'Persons', cur)]
      case 'DataSourceClassificationId':
        return [...acc, ...transform(CodeLookupBase, 'DataSourceClassification', cur)]
      case 'EnterpriseUnitRegId':
        return [...acc, ...transform(StatId, 'EnterpriseUnitRegId', cur)]
      case 'LegalUnitId':
        return [...acc, ...transform(StatId, 'LegalUnitId', cur)]
      case 'EntGroupId':
        return [...acc, ...transform(StatId, 'EntGroupId', cur)]
      case 'PersonStatUnits':
      case 'PersonEnterpriseGroups':
      case 'UnitType':
      case 'RegId':
      case 'LocalUnits':
      case 'LegalUnits':
        return acc
      case 'SizeId':
        return [...acc, ...transform(CodeLookupBase, 'SizeId', cur)]
      case 'UnitStatusId':
        return [...acc, ...transform(CodeLookupBase, 'UnitStatusId', cur)]
      case 'ReorgTypeId':
        return [...acc, ...transform(CodeLookupBase, 'ReorgTypeId', cur)]
      case 'RegistrationReasonId':
        return [...acc, ...transform(CodeLookupBase, 'RegistrationReasonId', cur)]
      case 'ForeignParticipationId':
        return [...acc, ...transform(ForeignParticipation, 'ForeignParticipationId', cur)]
      default:
        return [...acc, cur]
    }
  }, [])
}

const OrderOfVariablesOfDatabase = [
  ['StatId', 'StatIdDate', 'Name', 'ShortName', 'UnitStatusId', 'StatusDate'],
  ['TaxRegId', 'TaxRegDate'],
  ['ExternalId', 'ExternalIdType', 'ExternalIdDate'],
  ['DataSourceClassificationId', 'RegistrationReasonId'],
  ['EntGroupId', 'EnterpriseUnitRegId', 'EntRegIdDate', 'LegalUnitId'],
  ['TelephoneNo', 'EmailAddress', 'WebAddress'],
  ['Address'],
  ['ActualAddress'],
  ['PostalAddress'],
  ['Activities'],
  [
    'SizeId',
    'Turnover',
    'TurnoverYear',
    'TurnoverDate',
    'Employees',
    'NumOfPeopleEmp',
    'EmployeesYear',
    'EmployeesDate',
  ],
  ['LegalFormId'],
  ['InstSectorCodeId'],
  ['Persons'],
  ['ForeignParticipationId', 'ForeignParticipationCountriesUnits'],
  ['Market', 'FreeEconZone', 'Classified'],
  [
    'PrivCapitalShare',
    'MunCapitalShare',
    'StateCapitalShare',
    'ForeignCapitalShare',
    'ForeignCapitalCurrency',
    'TotalCapital',
  ],
  ['ReorgTypeId'],
  ['Notes'],
]

function orderFields(arr) {
  const sortedArr = []
  let remain = arr
  let groupNum = 1
  OrderOfVariablesOfDatabase.forEach((orderElem) => {
    orderElem.forEach((item) => {
      remain = remain.filter((elem) => {
        if (elem.name === item) {
          const f = elem
          f.groupNumber = groupNum
          sortedArr.push(f)
          return false
        }
        if (elem.name === 'ParentOrgLink') {
          return false
        }
        return true
      })
    })
    groupNum++
  })
  const result = sortedArr.concat(remain)
  return result
}

function transformObject(obj) {
  return {
    localUnit: addFlattened(orderFields(obj.localUnit)),
    legalUnit: addFlattened(orderFields(obj.legalUnit)),
    enterpriseUnit: addFlattened(orderFields(obj.enterpriseUnit)),
  }
}

export default transformObject
