import React from 'react'
import PropTypes from 'prop-types'
import R from 'ramda'
import { Container, Table, Button } from 'semantic-ui-react'

const getHeaders = R.pipe(R.head, R.dissoc('uid'), R.keys)
const { Header, Body, Footer, Row, HeaderCell, Cell } = Table

const List = ({ id, list, localize }) => {
  if (list.length === 0) return <h2>{localize('Empty')}</h2>
  const headers = getHeaders(list)
  return (
    <Container>
      <Table basic="very" compact="very" size="small" celled>
        <Header>
          <Row>
            {headers.map(key => (
              <HeaderCell key={key} content={localize(key)} textAlign="center" />
            ))}
          </Row>
        </Header>
        <Body>
          {list.map(({ uid, ...unit }) => (
            <Row key={uid}>
              {headers.map(key => <Cell key={key} content={unit[key]} textAlign="center" />)}
            </Row>
          ))}
        </Body>
        <Footer>
          <Row>
            <Cell colSpan={headers.length} textAlign="right">
              <Button
                as="a"
                href={`/api/sampleframes/${id}/preview/download`}
                target="__blank"
                content={localize('DownloadSampleFrame')}
                icon="download"
                color="blue"
                size="mini"
              />
            </Cell>
          </Row>
        </Footer>
      </Table>
    </Container>
  )
}

List.propTypes = {
  id: PropTypes.string.isRequired,
  list: PropTypes.arrayOf(PropTypes.shape({
    uid: PropTypes.number.isRequired,
  })).isRequired,
  localize: PropTypes.func.isRequired,
}

export default List
