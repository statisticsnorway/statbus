import React from 'react'
import { arrayOf, string, number, oneOfType, func, bool } from 'prop-types'
import { Message } from 'semantic-ui-react'
import Select from 'react-select'
import debounce from 'lodash/debounce'
import { map, equals } from 'ramda'

import { internalRequest } from 'helpers/request'

// TODO: should be configurable
const isNonNullable = x => [
  'localUnits',
  'legalUnits',
  'enterpriseUnits',
  'enterpriseUnitRegId',
  'enterpriseGroupRegId',
  'legalUnitId',
  'entGroupId',
].includes(x)
const withDefault = (options, localize) => [{ id: 0, name: localize('NotSelected') }, ...options]
const asOptions = map(x => ({ value: x.id, label: x.name }))
const waitTime = 250

class SelectField extends React.Component {

  static propTypes = {
    name: string.isRequired,
    label: string.isRequired,
    title: string,
    placeholder: string,
    value: oneOfType([arrayOf(number), number, arrayOf(string), string]),
    lookup: number,
    multiselect: bool,
    required: bool,
    touched: bool.isRequired,
    errors: arrayOf(string),
    disabled: bool,
    setFieldValue: func.isRequired,
    onBlur: func,
    localize: func.isRequired,
    pageSize: number,
  }

  static defaultProps = {
    value: '',
    title: undefined,
    placeholder: undefined,
    lookup: '',
    multiselect: false,
    required: false,
    errors: [],
    disabled: false,
    onBlur: _ => _,
    pageSize: 10,
  }

  state = { value: [] }

  componentWillReceiveProps(nextProps) {
    if (!equals(nextProps.value && this.state.value)) {
      this.setState({ value: nextProps.value })
    }
  }

  getOptions = (wildcard, page, callback) => {
    const { lookup, pageSize, name, multiselect, localize } = this.props
    return internalRequest({
      url: `/api/lookup/paginated/${lookup}`,
      queryParams: { page: page - 1, pageSize, wildcard },
      method: 'get',
      onSuccess: (data) => {
        const options = asOptions(
          isNonNullable(name) || multiselect
            ? data
            : withDefault(data, localize),
        )
        callback(null, { options })
      },
    })
  }

  handleLoadOptions = debounce(this.getOptions, waitTime)

  handleChange = (data) => {
    const { multiselect, setFieldValue, name } = this.props
    const value = multiselect
      ? data.map(x => x.value)
      : data !== null ? data.value : 0

    this.setState(
      { value: data },
      () => setFieldValue(name, value),
    )
  }

  render() {
    const {
      name, label: labelKey, title, placeholder,
      required, touched, errors, disabled, multiselect,
      onBlur, localize,
    } = this.props
    const { value } = this.state
    const label = localize(labelKey)
    const hasErrors = touched && errors.length !== 0
    return (
      <div className="field">
        <label htmlFor={name}>{label}</label>
        <Select.Async
          name={name}
          title={title || label}
          placeholder={localize(placeholder)}
          value={value}
          loadOptions={this.handleLoadOptions}
          multi={multiselect}
          onChange={this.handleChange}
          onBlur={onBlur}
          required={required}
          error={hasErrors}
          disabled={disabled}
          backspaceRemoves
          pagination
          search
          inputProps={{ type: 'react-select' }}
        />
        {hasErrors &&
          <Message title={label} list={errors.map(localize)} error />}
      </div>
    )
  }
}

export default SelectField
