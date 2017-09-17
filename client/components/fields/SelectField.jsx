import React from 'react'
import { arrayOf, string, number, oneOfType, func, bool, shape } from 'prop-types'
import { Message, Select as SemanticSelect } from 'semantic-ui-react'
import ReactSelect from 'react-select'
import debounce from 'lodash/debounce'
import { equals } from 'ramda'

import { hasValue, createPropType } from 'helpers/validation'
import { internalRequest } from 'helpers/request'

const withDefault = localize => options => [{ id: 0, name: localize('NotSelected') }, ...options]
const numOrStr = oneOfType([number, string])

const NameCodeOption = {
  transform: x => ({
    ...x,
    value: x.id,
    label: hasValue(x.code) ? `${x.code} ${x.name}` : x.name,
  }),
  // eslint-disable-next-line react/prop-types
  render: ({ name, code }) => (
    <div className="content">
      <div className="title">{name}</div>
      <strong className="description">{code}</strong>
    </div>
  ),
}

class SelectField extends React.Component {

  static propTypes = {
    name: string.isRequired,
    value: createPropType(
      props => props.multiselect
        ? arrayOf(numOrStr)
        : numOrStr,
    ),
    setFieldValue: func.isRequired,
    onBlur: func,
    errors: arrayOf(string),
    label: string.isRequired,
    title: string,
    placeholder: string,
    multiselect: bool,
    required: bool,
    touched: bool.isRequired,
    disabled: bool,
    renderOption: func,
    localize: func.isRequired,
    pageSize: number,
    waitTime: number,
    lookup: number,
    responseToOption: func,
    options: arrayOf(shape({
      value: numOrStr.isRequired,
      text: numOrStr.isRequired,
    })),
  }

  static defaultProps = {
    value: '',
    onBlur: _ => _,
    title: undefined,
    placeholder: undefined,
    multiselect: false,
    required: false,
    errors: [],
    disabled: false,
    renderOption: NameCodeOption.render,
    pageSize: 10,
    waitTime: 250,
    lookup: undefined,
    responseToOption: NameCodeOption.transform,
    options: undefined,
  }

  state = {
    value: hasValue(this.props.options)
      ? this.props.value
      : this.props.multiselect
        ? []
        : 0,
  }

  componentDidMount() {
    const { value: ids, lookup, multiselect, responseToOption, options } = this.props
    if (hasValue(options)) return
    internalRequest({
      url: `/api/lookup/${lookup}/GetById/`,
      queryParams: { ids },
      method: 'get',
      onSuccess: (value) => {
        if (hasValue(value)) {
          this.setState({
            value: multiselect
              ? value.map(responseToOption)
              : responseToOption(value[0]),
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

  componentWillUnmount() {
    this.handleLoadOptions.cancel()
  }

  loadOptions = (wildcard, page, callback) => {
    const {
      lookup, pageSize, multiselect, required, localize, responseToOption,
    } = this.props
    internalRequest({
      url: `/api/lookup/paginated/${lookup}`,
      queryParams: { page: page - 1, pageSize, wildcard },
      method: 'get',
      onSuccess: (data) => {
        let options = multiselect || !required ? data : withDefault(localize)(data)
        if (responseToOption) options = options.map(responseToOption)
        callback(null, { options })
      },
    })
  }

  handleLoadOptions = debounce(this.loadOptions, this.props.waitTime)

  handleAsyncSelect = (data) => {
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

  handlePlainSelect = (_, { value }) => {
    const { setFieldValue, name } = this.props
    if (!equals(this.state.value, value)) {
      this.setState(
        { value },
        () => setFieldValue(name, value),
      )
    }
  }

  render() {
    const {
      localize, label: labelKey, touched, errors: errorKeys, options, title: titleKey,
      placeholder: placeholderKey, multiselect, renderOption, required, disabled, onBlur,
    } = this.props
    const hasErrors = touched && hasValue(errorKeys)
    const label = localize(labelKey)
    const title = titleKey ? localize(titleKey) : label
    const placeholder = placeholderKey ? localize(placeholderKey) : label
    const [Select, ownProps] = hasValue(options)
      ? [SemanticSelect, {
        onChange: this.handlePlainSelect,
        options,
        title,
        error: hasErrors,
        multiple: multiselect,
      }]
      : [ReactSelect.Async, {
        onChange: this.handleAsyncSelect,
        loadOptions: this.handleLoadOptions,
        optionRenderer: renderOption,
        inputProps: { type: 'react-select' },
        className: hasErrors ? 'ui error' : 'ui',
        multi: multiselect,
        backspaceRemoves: true,
        searchable: true,
        pagination: true,
      }]
    return (
      <div className="field">
        <label htmlFor={name}>{label}</label>
        <Select
          {...ownProps}
          value={this.state.value}
          onBlur={onBlur}
          name={name}
          placeholder={placeholder}
          required={required}
          disabled={disabled}
        />
        {hasErrors &&
          <Message title={label} list={errorKeys.map(localize)} error />}
      </div>
    )
  }
}

export default SelectField
