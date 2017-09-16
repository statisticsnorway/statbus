import React from 'react'
import { arrayOf, string, number, oneOfType, func, bool, shape } from 'prop-types'
import { Message, Select } from 'semantic-ui-react'
import { Async as AsyncSelect } from 'react-select'
import debounce from 'lodash/debounce'
import { pipe, map, equals } from 'ramda'

import { hasValue } from 'helpers/schema'
import { internalRequest } from 'helpers/request'
import * as NameCodeOption from './NameCodeOption'

// TODO: should be configurable
const nonNullableFields = [
  'localUnits',
  'legalUnits',
  'enterpriseUnits',
  'enterpriseUnitRegId',
  'enterpriseGroupRegId',
  'legalUnitId',
  'entGroupId',
]

const withDefault = localize => options => [{ id: 0, name: localize('NotSelected') }, ...options]

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
    options: arrayOf(shape({
      value: oneOfType([number, string]).isRequired,
      label: oneOfType([number, string]).isRequired,
    })),
    renderOption: func,
    responseItemToOption: func,
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
    options: undefined,
    renderOption: NameCodeOption.render,
    responseItemToOption: NameCodeOption.transform,
  }

  state = {
    value: hasValue(this.props.options)
      ? this.props.value
      : this.props.multiselect
        ? []
        : 0,
  }

  componentDidMount() {
    const { value: ids, lookup, multiselect, responseItemToOption, options } = this.props
    if (hasValue(options)) return
    internalRequest({
      url: `/api/lookup/${lookup}/GetById/`,
      queryParams: { ids },
      method: 'get',
      onSuccess: (value) => {
        if (hasValue(value)) {
          this.setState({
            value: multiselect
              ? value.map(responseItemToOption)
              : responseItemToOption(value[0]),
          })
        }
      },
    })
  }

  componentWillReceiveProps(nextProps) {
    if (!equals(nextProps.value && this.state.value)) {
      this.setState({ value: nextProps.value })
    }
  }

  loadOptions = (wildcard, page, callback) => {
    const {
      lookup, pageSize, multiselect, localize, responseItemToOption,
    } = this.props
    internalRequest({
      url: `/api/lookup/paginated/${lookup}`,
      queryParams: { page: page - 1, pageSize, wildcard },
      method: 'get',
      onSuccess: (data) => {
        // TODO: take required from props when (non)nullable fields will be configurable
        const required = !nonNullableFields.includes(name)
        const pipeline = [
          ...(multiselect || !required ? [] : [withDefault(localize)]),
          ...(responseItemToOption ? [map(responseItemToOption)] : []),
        ]
        callback(null, { options: pipe(pipeline)(data) })
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

  render() {
    const {
      name, label: labelKey, title, placeholder, options,
      required, touched, errors, disabled, multiselect,
      renderOption, onBlur, localize,
    } = this.props
    const { value } = this.state
    const label = localize(labelKey)
    const hasErrors = touched && errors.length !== 0
    const [Component, props] = hasValue(options)
      ? [Select, { options }]
      : [AsyncSelect, { loadOptions: this.handleLoadOptions, pagination: true }]
    return (
      <div className="field">
        <label htmlFor={name}>{label}</label>
        <Component
          {...props}
          value={value}
          onChange={this.handleChange}
          onBlur={onBlur}
          inputProps={{ type: 'react-select' }}
          optionRenderer={renderOption}
          name={name}
          title={title || label}
          placeholder={localize(placeholder)}
          required={required}
          error={hasErrors}
          disabled={disabled}
          multi={multiselect}
          backspaceRemoves
          searchable
        />
        {hasErrors &&
          <Message title={label} list={errors.map(localize)} error />}
      </div>
    )
  }
}

export default SelectField
