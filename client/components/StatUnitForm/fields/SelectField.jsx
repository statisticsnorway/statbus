import React from 'react'
import { arrayOf, string, number, oneOfType, func, bool } from 'prop-types'
import { Message } from 'semantic-ui-react'
import Select from 'react-select'
import debounce from 'lodash/debounce'
import { map, equals } from 'ramda'

import { nonEmpty } from 'helpers/schema'
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
const asOptions = map(x => ({ value: x.id, label: nonEmpty(x.code) ? `${x.code} ${x.name}` : x.name, name: x.name, code: x.code }))

class SelectField extends React.Component {

  static propTypes = {
    name: string.isRequired,
    label: string.isRequired,
    title: string,
    placeholder: string,
    value: oneOfType([number, string, arrayOf(number), arrayOf(string)]),
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
    waitTime: number,
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
    waitTime: 250,
  }

  state = { value: this.props.multiselect ? [] : 0 }

  componentDidMount() {
    const { value: ids, lookup } = this.props
    internalRequest({
      url: `/api/lookup/${lookup}/GetById/`,
      queryParams: { ids },
      method: 'get',
      onSuccess: (value) => {
        if (value === null || value.length === 0) return
        this.setState({ value: this.props.multiselect
            ? asOptions(value)
            : asOptions(value)[0],
        })
      },
    })
  }

  componentWillReceiveProps(nextProps) {
    if (!equals(nextProps.value && this.state.value)) {
      this.setState({ value: nextProps.value })
    }
  }

  loadOptions = (wildcard, page, callback) => {
    const { lookup, pageSize, name, multiselect, localize } = this.props
    internalRequest({
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

  handleLoadOptions = debounce(this.loadOptions, this.props.waitTime)

  handleChange = (data) => {
    const { multiselect, setFieldValue, name } = this.props
    const value = data !== null ? data : { value: 0 }
    if (!equals(this.state.value, value)) {
      const fieldValue = multiselect
        ? value.map(x => x.value)
        : value.value
      this.setState(
        { value },
        () => setFieldValue(name, fieldValue),
      )
    }
  }

  renderOption = (option) => (
      <div className="content">
        <div className="title">{option.name}</div>
        <strong className="description">{option.code}</strong>
      </div>
    )

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
          searchable
          inputProps={{ type: 'react-select' }}
          optionRenderer={this.renderOption}
        />
        {hasErrors &&
          <Message title={label} list={errors.map(localize)} error />}
      </div>
    )
  }
}

export default SelectField
