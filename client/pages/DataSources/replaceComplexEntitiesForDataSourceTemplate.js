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
  Id: 'Id',
}

const ForeignParticipationCountriesUnits = {
  ForeignParticipationCountry: [
    'ForeignParticipationCountry',
    {
      ...ForeignParticipationCountry,
    },
  ],
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

function transform(shape, prefix) {
  return pathsOf(shape, prefix).map(pathToMetaEntry)
}

function addFlattened(arr) {
  return arr.reduce((acc, cur) => {
    switch (cur.name) {
      case 'Activities':
        return [...acc, ...transform(Activities, 'Activities')]
      case 'Address':
        return [...acc, ...transform(Address, 'Address')]
      case 'ActualAddress':
        return [...acc, ...transform(Address, 'ActualAddress')]
      case 'PostalAddress':
        return [...acc, ...transform(Address, 'PostalAddress')]
      case 'ForeignParticipationCountriesUnits':
        return [
          ...acc,
          ...transform(ForeignParticipationCountriesUnits, 'ForeignParticipationCountriesUnits'),
        ]
      case 'InstSectorCodeId':
        return [...acc, ...transform(CodeLookupBase, 'InstSectorCode')]
      case 'LegalFormId':
        return [...acc, ...transform(CodeLookupBase, 'LegalForm')]
      case 'Persons':
        return [...acc, ...transform(Persons, 'Persons')]
      case 'DataSourceClassificationId':
        return [...acc, ...transform(CodeLookupBase, 'DataSourceClassification')]
      case 'EnterpriseUnitRegId':
        return [...acc, ...transform(StatId, 'EnterpriseUnitRegId')]
      case 'LegalUnitId':
        return [...acc, ...transform(StatId, 'LegalUnitId')]
      case 'EntGroupId':
        return [...acc, ...transform(StatId, 'EntGroupId')]
      case 'PersonStatUnits':
      case 'PersonEnterpriseGroups':
      case 'UnitType':
      case 'RegId':
      case 'LocalUnits':
      case 'LegalUnits':
        return acc
      case 'SizeId':
        return [...acc, ...transform(LookupBase, 'Size')]
      case 'UnitStatusId':
        return [...acc, ...transform(CodeLookupBase, 'UnitStatus')]
      case 'ReorgTypeId':
        return [...acc, ...transform(CodeLookupBase, 'ReorgType')]
      case 'RegistrationReasonId':
        return [...acc, ...transform(CodeLookupBase, 'RegistrationReason')]
      default:
        return [...acc, cur]
    }
  }, [])
}

const OrderOfVariablesOfDatabase = [
  'StatId',
  'StatIdDate',
  'Name',
  'ShortName',
  'UnitStatusId',
  'StatusDate',
  'TaxRegId',
  'TaxRegDate',
  'ExternalId',
  'ExternalIdType',
  'ExternalIdDate',
  'DataSourceClassificationId',
  'RegistrationReasonId',
  'EntGroupId',
  'EnterpriseUnitRegId',
  'LegalUnitId',
  'TelephoneNo',
  'EmailAddress',
  'WebAddress',
  'Address',
  'ActualAddress',
  'PostalAddress',
  'Activities',
  'SizeId',
  'Turnover',
  'TurnoverYear',
  'TurnoverDate',
  'Employees',
  'NumOfPeopleEmp',
  'EmployeesYear',
  'EmployeesDate',
  'LegalFormId',
  'InstSectorCodeId',
  'Persons',
  'ForeignParticipationCountriesUnits',
  'Market',
  'FreeEconZone',
  'Classified',
  'TotalCapital',
  'Notes',
  'ReorgTypeId',
]

function orderFields(arr) {
  const sortedArr = []
  let remain = arr
  OrderOfVariablesOfDatabase.forEach((orderElem) => {
    remain = remain.filter((elem) => {
      if (elem.name === orderElem) {
        sortedArr.push(elem)
        return false
      }
      return true
    })
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
