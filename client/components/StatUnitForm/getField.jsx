import React from 'react'

import { statUnitFormFieldTypes } from 'helpers/enums'
import CheckField from './fields/CheckField'
import DateTimeField from './fields/DateTimeField'
import NumberField from './fields/NumberField'
import TextField from './fields/TextField'
import SelectField from './fields/SelectField'
import ActivitiesField from './fields/ActivitiesField'
import PersonsField from './fields/PersonsField'
import AddressField from './fields/AddressField'
import SearchField from './fields/SearchField'

export default (type, ...props) => {
  switch (statUnitFormFieldTypes.get(type)) {
    case 'Boolean':
      return <CheckField {...props} />
//           key={item.name}
//           name={item.name}
//           value={item.value}
//           onChange={onChange}
//           labelKey={item.localizeKey}
//           localize={localize}
//           errors={errors}
    case 'DateTime':
      return <DateTimeField {...props} />
//           key={item.name}
//           name={item.name}
//           value={item.value}
//           onChange={onChange}
//           required={item.isRequired}
//           labelKey={item.localizeKey}
//           localize={localize}
//           errors={errors}
    case 'Float':
    case 'Integer':
      return <NumberField {...props} />
//           key={item.name}
//           name={item.name}
//           value={item.value}
//           onChange={onChange}
//           required={item.isRequired}
//           labelKey={item.localizeKey}
//           localize={localize}
//           errors={errors}
    case 'String':
      return <TextField {...props} />
//           key={item.name}
//           name={item.name}
//           value={item.value}
//           onChange={onChange}
//           required={item.isRequired}
//           labelKey={item.localizeKey}
//           localize={localize}
//           errors={errors}
    case 'MultiReference':
      return <SelectField {...props} multiselect />
//           key={item.name}
//           name={item.name}
//           value={item.value}
//           onChange={onChange}
//           required={item.isRequired}
//           lookup={item.lookup}
//           labelKey={item.localizeKey}
//           localize={localize}
//           errors={errors}
//           multiselect
    case 'Reference':
      return <SelectField {...props} />
//           key={item.name}
//           name={item.name}
//           value={item.value}
//           onChange={onChange}
//           required={item.isRequired}
//           labelKey={item.localizeKey}
//           lookup={item.lookup}
//           localize={localize}
//           errors={errors}
    case 'Activities':
      return <ActivitiesField {...props} />
//           key={item.name}
//           name={item.name}
//           data={item.value}
//           onChange={onChange}
//           labelKey={item.localizeKey}
//           localize={localize}
//           errors={errors}
    case 'Addresses':
      return <AddressField {...props} />
//           key={item.name}
//           name={item.name}
//           data={item.value}
//           onChange={onChange}
//           localize={localize}
//           errors={errors}
    case 'Persons':
      return <PersonsField {...props} />
//           key={item.name}
//           name={item.name}
//           data={item.value}
//           onChange={onChange}
//           labelKey={item.localizeKey}
//           localize={localize}
//           errors={errors}
    case 'SearchComponent':
      return <SearchField {...props} />
//           key={item.name}
//           name={item.name}
//           value={item.value}
//           required={item.isRequired}
//           onChange={onChange}
//           localize={localize}
//           errors={errors}
    default:
      throw new Error(props)
  }
}
