import React from 'react'
import { arrayOf, func, string, oneOfType, number } from 'prop-types'
import { Message } from 'semantic-ui-react'

import SearchInput from 'components/SearchInput'
import sources from 'components/SearchInput/sources'
import { internalRequest } from 'helpers/request'

const stubF = _ => _
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
    setFieldValue: func.isRequired,
    localize: func.isRequired,
  }

  static defaultProps = {
    value: '',
    data: {},
    errors: [],
  }

  state = {
    data: {},
  }

  componentDidMount() {
    const { name, value } = this.props
    const { editUrl } = getSearchData(name)
    if (value) {
      internalRequest({
        url: `${editUrl}${value}`,
        method: 'get',
        onSuccess: (data) => {
          this.setState({ data })
        },
      })
    }
  }

  setLookupValue = (data) => {
    const { name, setFieldValue } = this.props
    this.setState({ data }, () => setFieldValue(name, data.id))
  }

  render() {
    const { localize, name, errors } = this.props
    const { data } = this.state
    const searchData = { ...getSearchData(name), data }
    const hasErrors = errors.length > 0
    return (
      <div className={`ui field ${hasErrors ? 'error' : ''}`}>
        <SearchInput
          localize={localize}
          searchData={searchData}
          onValueSelected={this.setLookupValue}
          onValueChanged={stubF}
        />
        {hasErrors &&
          <Message title={localize(searchData.label)} content={errors.map(localize)} error />}
      </div>
    )
  }
}

export default SearchField
