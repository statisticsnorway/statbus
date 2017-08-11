import React from 'react'
import { func, string, oneOfType, number } from 'prop-types'

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
      throw new Error(`SearchField couldn't find search source for given name "${name}"`)
  }
}

class SearchField extends React.Component {

  static propTypes = {
    localize: func.isRequired,
    value: oneOfType([number, string]),
    name: string.isRequired,
    onChange: func.isRequired,
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
    const { name, onChange } = this.props
    this.setState({ data }, () => onChange({ name, value: data.id }))
  }

  render() {
    const { localize, name } = this.props
    const { data } = this.state
    const searchData = { ...getSearchData(name), data }
    return (
      <SearchInput
        localize={localize}
        searchData={searchData}
        onValueSelected={this.setLookupValue}
        onValueChanged={stubF}
      />
    )
  }
}

export default SearchField
