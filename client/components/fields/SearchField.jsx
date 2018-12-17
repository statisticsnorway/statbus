import React from 'react'
import { arrayOf, func, string, oneOfType, number, bool } from 'prop-types'
import { Message } from 'semantic-ui-react'
import { isEmpty } from 'ramda'

import SearchInput from 'components/SearchInput'
import sources from 'components/SearchInput/sources'
import { internalRequest } from 'helpers/request'

const getSearchData = (name) => {
  switch (name) {
    case 'instSectorCodeId':
      return sources.sectorCode
    case 'legalFormId':
      return sources.legalForm
    case 'parentOrgLink':
      return sources.parentOrgLink
    case 'reorgReferences':
      return sources.reorgReferences
    default:
      throw new Error(`SearchField couldn't find search source for given name: "${name}"`)
  }
}

class SearchField extends React.Component {
  static propTypes = {
    name: string.isRequired,
    value: oneOfType([number, string]),
    errors: arrayOf(string),
    disabled: bool,
    onChange: func.isRequired,
    localize: func.isRequired,
    required: bool.isRequired,
  }

  static defaultProps = {
    value: '',
    errors: [],
    disabled: false,
    required: false,
  }

  state = {
    value: {},
  }

  componentDidMount() {
    const { name, value } = this.props
    const { editUrl } = getSearchData(name)
    if (value) {
      internalRequest({
        url: `${editUrl}${value}`,
        method: 'get',
        onSuccess: data => this.setState({ value: data }),
      })
    }
  }

  componentWillReceiveProps(nextProps) {
    if (isEmpty(nextProps.value)) {
      this.setState({ value: '' })
    }
  }

  setLookupValue = (data) => {
    const { name, onChange } = this.props
    this.setState({ value: data.name }, () => onChange(undefined, { name, value: data.id }))
  }

  handleChange = (data) => {
    this.setState({ value: typeof data !== 'object' ? data : data.name })
  }

  render() {
    const { localize, name, errors: errorKeys, disabled, required } = this.props
    const { value } = this.state
    const searchData = { ...getSearchData(name), value }
    const hasErrors = errorKeys.length > 0
    return (
      <div className={`ui field ${hasErrors ? 'error' : ''}`}>
        <SearchInput
          searchData={searchData}
          onValueChanged={this.handleChange}
          onValueSelected={this.setLookupValue}
          disabled={disabled}
          localize={localize}
          required={required}
        />
        {hasErrors && (
          <Message title={localize(searchData.label)} content={errorKeys.map(localize)} error />
        )}
      </div>
    )
  }
}

export default SearchField
