import React from 'react'
import { arrayOf, string, number, oneOfType, func, bool, shape } from 'prop-types'
import { Message, Select as SemanticUiSelect, Label } from 'semantic-ui-react'
import ReactSelect from 'react-select'
import debounce from 'lodash/debounce'
import R from 'ramda'

import { hasValue, createPropType } from 'helpers/validation'
import { internalRequest } from 'helpers/request'
import { getNewName } from '../../helpers/locale'

import styles from './styles.pcss'

const notSelected = { value: undefined, text: 'NotSelected' }

const NameCodeOption = {
  transform: x => ({
    ...x,
    value: x.id,
    label: getNewName(x),
  }),
  // eslint-disable-next-line react/prop-types
  render: localize => ({ id, name, code }) => (
    <div className="content">
      <div className="title">
        {code && <div className={styles['select-field-code']}>{code}</div>}
        {code && <br />}
        {id === notSelected.value ? localize(name) : name}
        <hr />
      </div>
    </div>
  ),
}

// eslint-disable-next-line react/prop-types
const createRemovableValueComponent = localize => ({ value, onRemove }) => (
  <Label
    content={value.value === notSelected.value ? localize(value.label) : value.label}
    onRemove={() => onRemove(value)}
    removeIcon="delete"
    color="blue"
    basic
  />
)

// eslint-disable-next-line react/prop-types
const createValueComponent = localize => ({ value: { value, label } }) => (
  <div className="Select-value">
    <span className="Select-value-label" role="option" aria-selected="true">
      {value === notSelected.value ? localize(notSelected.text) : label}
    </span>
  </div>
)

const numOrStr = oneOfType([number, string])

class SelectField extends React.Component {
  static propTypes = {
    name: string.isRequired,
    value: createPropType(props => (props.multiselect ? arrayOf(numOrStr) : numOrStr)),
    onChange: func.isRequired,
    onBlur: func,
    errors: arrayOf(string),
    label: string,
    title: string,
    placeholder: string,
    multiselect: bool,
    required: bool,
    touched: bool,
    disabled: bool,
    inline: bool,
    width: numOrStr,
    createOptionComponent: func,
    localize: func.isRequired,
    popuplocalizedKey: string,
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
    value: undefined,
    onBlur: R.identity,
    label: undefined,
    title: undefined,
    placeholder: undefined,
    multiselect: false,
    required: false,
    errors: [],
    disabled: false,
    inline: false,
    width: undefined,
    createOptionComponent: NameCodeOption.render,
    pageSize: 10,
    waitTime: 250,
    lookup: undefined,
    responseToOption: NameCodeOption.transform,
    options: undefined,
    touched: false,
    popuplocalizedKey: undefined,
  }

  state = {
    value: hasValue(this.props.value)
      ? this.props.value
      : this.props.multiselect ? [] : notSelected.value,
    optionsFetched: false,
  }

  componentDidMount() {
    if (hasValue(this.props.options)) return
    const { value: ids, lookup, multiselect, responseToOption } = this.props
    internalRequest({
      url: `/api/lookup/${lookup}/GetById/`,
      queryParams: { ids },
      method: 'get',
      onSuccess: (value) => {
        if (hasValue(value)) {
          this.setState({
            value: multiselect ? value.map(responseToOption) : responseToOption(value[0]),
          })
        }
      },
    })
  }

  componentWillReceiveProps(nextProps) {
    const { locale, multiselect, responseToOption } = this.props
    const { value } = this.state
    if (!R.equals(nextProps.value && value)) {
      this.setState({ value: nextProps.value })
    }
    if (R.isNil(nextProps.value) || (R.is(Array, nextProps.value) && R.isEmpty(nextProps.value))) {
      this.setState({ value: '' }, () =>
        this.props.onChange(undefined, { ...this.props, value: '' }))
    }
    if (nextProps.locale !== locale) {
      const currValue = hasValue(value) ? value : []
      this.setState({
        value: multiselect ? currValue.map(responseToOption) : responseToOption(currValue),
      })
    }
  }

  componentWillUnmount() {
    this.handleLoadOptions.cancel()
  }

  loadOptions = (wildcard, page, callback) => {
    const { lookup, pageSize, multiselect, required, responseToOption } = this.props
    const { optionsFetched } = this.state
    internalRequest({
      url: `/api/lookup/paginated/${lookup}`,
      queryParams: { page: page - 1, pageSize, wildcard },
      method: 'get',
      onSuccess: (data) => {
        let options =
          multiselect || !required || optionsFetched
            ? data
            : [{ id: notSelected.value, name: notSelected.text }, ...data]
        if (responseToOption) options = options.map(responseToOption)
        if (optionsFetched) {
          callback(null, { options })
        } else {
          this.setState({ optionsFetched: true }, () => {
            callback(null, { options })
          })
        }
      },
    })
  }

  handleLoadOptions = debounce(this.loadOptions, this.props.waitTime)

  handleAsyncSelect = (data) => {
    const { multiselect, onChange } = this.props
    const raw = data !== null ? data : { value: notSelected.value }
    const value = multiselect ? raw.map(x => x.value) : raw.value
    if (!R.equals(this.state.value, value)) {
      this.setState({ value: raw }, () => onChange(undefined, { ...this.props, value }, data))
    }
  }

  handlePlainSelect = (event, { value, ...data }) => {
    const nextData = { ...data, ...this.props, value }
    if (!R.equals(this.state.value, value)) {
      this.setState({ value }, () => this.props.onChange(event, nextData))
    }
  }

  render() {
    const {
      name,
      label: labelKey,
      touched,
      errors: errorKeys,
      options,
      multiselect,
      title: titleKey,
      placeholder: placeholderKey,
      createOptionComponent,
      required,
      disabled,
      inline,
      width,
      onBlur,
      localize,
    } = this.props
    const hasErrors = touched && hasValue(errorKeys)
    const label = labelKey !== undefined ? localize(labelKey) : undefined
    const title = titleKey ? localize(titleKey) : label
    const placeholder = placeholderKey ? localize(placeholderKey) : label
    const hasOptions = hasValue(options)
    const [Select, ownProps] = hasOptions
      ? [
        SemanticUiSelect,
        {
          onChange: this.handlePlainSelect,
          error: hasErrors,
          multiple: multiselect,
          options:
              multiselect || !required
                ? options
                : [{ value: notSelected.value, text: localize(notSelected.text) }, ...options],
          required,
          title,
          inline,
          width,
        },
      ]
      : [
        ReactSelect.Async,
        {
          onChange: this.handleAsyncSelect,
          loadOptions: this.handleLoadOptions,
          valueComponent: multiselect
            ? createRemovableValueComponent(localize)
            : createValueComponent(localize),
          optionRenderer: createOptionComponent(localize),
          inputProps: { type: 'react-select', name },
          className: hasErrors ? 'react-select--error' : '',
          multi: multiselect,
          backspaceRemoves: true,
          searchable: true,
          pagination: true,
          clearable: false,
          filterOptions: R.identity,
          required,
        },
      ]
    const className = `field${!hasOptions && required ? ' required' : ''}`
    return (
      <div className={className} style={{ opacity: `${disabled ? 0.25 : 1}` }}>
        {label !== undefined && <label htmlFor={name}>{label}</label>}
        <Select
          {...ownProps}
          value={this.state.value}
          onBlur={onBlur}
          name={name}
          placeholder={placeholder}
          disabled={disabled}
          openOnFocus
        />
        {hasErrors && (
          <Message title={label} list={errorKeys.map(localize)} compact={hasOptions} error />
        )}
      </div>
    )
  }
}

export default SelectField
