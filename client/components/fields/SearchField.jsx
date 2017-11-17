import React from 'react'
import { arrayOf, func, string, oneOfType, number, bool } from 'prop-types'
import { Message } from 'semantic-ui-react'

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
    setFieldValue: func.isRequired,
    localize: func.isRequired,
  }

  static defaultProps = {
    value: '',
    data: {},
    errors: [],
    disabled: false,
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
        onSuccess: (data) => {
          this.setState({ value: data })
        },
      })
    }
  }

  setLookupValue = (data) => {
    const { name, setFieldValue } = this.props
    this.setState({ value: data.name }, () => setFieldValue(name, data.id))
  }

  handleChange = (data) => {
    this.setState({ value: typeof (data) !== 'object' ? data : data.name })
  }

  render() {
    const { localize, name, errors: errorKeys, disabled } = this.props
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
        />
        {hasErrors && (
          <Message title={localize(searchData.label)} content={errorKeys.map(localize)} error />
        )}
      </div>
    )
  }
}

export default SearchField
