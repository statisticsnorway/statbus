import React from 'react'
import { arrayOf, string, number, oneOfType, func, bool } from 'prop-types'
import { Message, Form } from 'semantic-ui-react'
import Select from 'react-select'
import debounce from 'lodash/debounce'

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
    onBlur: () => { },
  }

  state = {
    lookup: [],
  }

  componentDidMount() {
    // internalRequest({
    //   url: `/api/lookup/${this.props.lookup}`,
    //   method: 'get',
    //   onSuccess: (value) => {
    //     const lookup = isNonNullable(this.props.name)
    //       ? value
    //       : withDefault(value, this.props.localize)
    //     this.setState({ lookup })
    //   },
    // })
  }

  componentWillReceiveProps(nextProps) {
    if (!isNonNullable(nextProps.name) && this.props.localize.lang !== nextProps.localize.lang) {
      this.setState(prev => ({ lookup: withDefault(prev.lookup.slice(1), nextProps.localize) }))
    }
  }

  getOptions = debounce((input, pageNumber, callback) => {
    internalRequest({
      url: `/api/lookup/paginated/${this.props.lookup}`,
      queryParams: { page: pageNumber - 1, pageSize: 10, wildcard: input },
      method: 'get',
      onSuccess: (value) => {
        const lookup = isNonNullable(this.props.name)
          ? value
          : withDefault(value, this.props.localize)
        this.setState({ lookup })
        callback(null, { options: lookup })
      },
    })
  }, waitTime)

  handleChange = (value) => {
    console.log('value', value, this.props.name)
    this.props.setFieldValue(this.props.name, value.value)
  }

  render() {
    const {
      name, value, label: labelKey, title, placeholder,
      required, touched, errors, disabled,
      onBlur, localize,
    } = this.props
    const label = localize(labelKey)
    const hasErrors = touched && errors.length !== 0
    const options = this.state.lookup.map(x => ({ value: x.id, text: x.name }))
    console.log('this.state.lookup', this.state.lookup)
    return (
      <div className="field">
        <Select.Async
          name={name}
          label={label}
          title={title || label}
          placeholder={localize(placeholder)}
          value={this.state.lookup.name} // did not dispaly
          loadOptions={this.getOptions}
          multi={this.props.multiselect}
          onChange={this.handleChange}
          onBlur={onBlur}
          required={required}
          error={hasErrors}
          disabled={disabled}
          search
          labelKey="name"
          valueKey="id"

          pagination
          backspaceRemoves
        />
        {hasErrors &&
          <Message title={label} list={errors.map(localize)} error />}
      </div>
    )
  }


//   <div className="field">
//   <Form.Select
//     name={name}
//     label={label}
//     title={title || label}
//     placeholder={localize(placeholder)}
//     value={value}
//     options={options}
//     multiple={this.props.multiselect}
//     onChange={this.handleChange}
//     onBlur={onBlur}
//     required={required}
//     error={hasErrors}
//     disabled={disabled}
//     search
//   />
//   {hasErrors &&
//     <Message title={label} list={errors.map(localize)} error />}
// </div>


}

export default SelectField
